module Main where

import Prelude

import Effect (Effect)
import Effect.Class.Console (log)
import Effect.Exception (throw)
import Data.Foldable (intercalate)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Traversable (traverse)
import Data.Maybe (Maybe(..))
import Options.Applicative.Extra (execParser)
import Data.Bifunctor (lmap)
import Node.Process (exit)
import Node.Buffer (toString, fromString) as Buff
import Node.Encoding (Encoding(..)) as Buff
import Node.FS.Sync (readFile, writeFile, exists) as FS
import Data.Argonaut.Parser (jsonParser) as A
import Data.Argonaut.Core (stringify) as A
import Data.Argonaut.Decode (decodeJson) as A
import Data.Argonaut.Decode.Error (printJsonDecodeError) as A
import Data.Argonaut.Encode (encodeJson) as A

import Hours.Clargs (cli, Clargs(..), Cmd(..))
import Hours.Types (Journal, Event(..), EventPayload(..))
import Hours.Time (getNow, isToday)
import Hours.Simulate (simulate)
import Hours.Prettify (prettifyApp, prettifyEvent)

main :: Effect Unit
main = do

  Clargs { journalLoc, cmd } <- execParser cli

  journal <- readJournal journalLoc

  case cmd of
    Cmd_Status { todayOnly } -> do
      journal' <- if todayOnly then filterToday journal else pure journal
      app <- simulate journal' # throwLeft "simulating"
      log =<< prettifyApp app

    Cmd_History -> do
      log $ journal # map prettifyEvent # intercalate "\n\n"

    Cmd_Undo -> do
      let journal' = Array.dropEnd 1 journal
      app <- simulate journal' # throwLeft "simulating"
      log =<< prettifyApp app
      writeJournal journalLoc journal'

    Cmd_Append mkEvent -> do
      now <- getNow
      let event = mkEvent { now }
      let journal' = Array.snoc journal event
      case simulate journal' of
        Left err -> do
          log err
          exit 1
        Right app -> do
          log =<< prettifyApp app
          writeJournal journalLoc journal'

  where

  filterToday :: Journal -> Effect Journal
  filterToday journal = do
    let shouldKeep (Event event) = disj <$> isToday event.timestamp <*> isTimeless event
    journal' <- journal # filterM shouldKeep
    pure journal'

    where
      isTimeless event = pure $ case event.payload of
        EventPayload_NewTopic    _ -> true
        EventPayload_RetireTopic _ -> true
        EventPayload_LogWork     _ -> false
        EventPayload_WorkStart   _ -> false
        EventPayload_WorkStop    _ -> false
        EventPayload_Billed      _ -> true

  filterM :: forall m a. Monad m => (a -> m Boolean) -> Array a -> m (Array a)
  filterM p =
    traverse (\x -> do
      b <- p x
      pure $ if b then Just x else Nothing)
    >>> map Array.catMaybes

  readJournal :: String -> Effect Journal
  readJournal loc = do
    journalExists <- FS.exists loc
    if not journalExists then
      pure []
    else do
      buff <- FS.readFile loc
      text <- Buff.toString Buff.UTF8 buff
      json <- A.jsonParser text # throwLeft "parsing json"
      journal <- A.decodeJson json # lmap A.printJsonDecodeError # throwLeft "parsing journal"
      pure journal

  writeJournal :: String -> Journal -> Effect Unit
  writeJournal loc journal = do
    let text = A.stringify $ A.encodeJson journal
    buff <- Buff.fromString text Buff.UTF8
    FS.writeFile loc buff

  throwLeft :: forall a. String -> Either String a -> Effect a
  throwLeft while = case _ of
    Left err -> throw ("Error while " <> while <> ": " <> err)
    Right val -> pure val
