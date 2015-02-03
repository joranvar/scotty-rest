{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Database where

import GHC.Generics
import Data.Foldable
import Web.Scotty.Trans hiding (get, put)
import Web.Scotty.Rest
import Network.Wai.Middleware.RequestLogger
import Data.Text.Lazy hiding (map)
import Database.SQLite.Simple hiding (fold)
import Control.Exception (try, SomeException)
import Control.Monad.State
import Data.Aeson


data Message = Message {
  message :: Text
} deriving Generic

instance FromJSON Message

type ScottyRestDbM = ActionT RestException (StateT (Maybe Connection) IO)

app :: IO ()
app = scottyT 7000 (`evalStateT` Nothing) (`evalStateT` Nothing) $ do
  middleware logStdoutDev
  rest "/messages" defaultConfig { allowedMethods       = allowed
                                 , serviceAvailable     = available
                                 , contentTypesProvided = provided
                                 , contentTypesAccepted = accepted
                                 }
  where
    available = do
      -- Try to open the database, if we fail, the service is not available, so
      -- we return False.
      connection <- liftIO (try (open "test.db") :: IO (Either SomeException Connection))
      case connection of
           Left ex    -> (html . pack . show) ex >> return False
           Right conn -> do
             liftIO $ execute_ conn "CREATE TABLE IF NOT EXISTS messages (message varchar)"
             lift (put (Just conn)) -- store the database connection handle in the state
             return True
    allowed = return [GET, HEAD, POST, OPTIONS]
    provided = return [
        ("text/html", do
          Just conn <- lift get
          messages <- liftIO $ query_ conn "SELECT message FROM messages LIMIT 10"
          text $ fold $ map (\(Only m) -> pack m `snoc` '\n') messages
        ),
        ("application/json", do
          Just conn <- lift get
          messages <- liftIO $ query_ conn "SELECT message FROM messages LIMIT 10"
          text $ fold $ map (\(Only m) -> pack m `snoc` '\n') messages
        )
      ]
    accepted = return [
        ("application/json", do
          Just conn <- lift get
          Message msg <- jsonData
          liftIO $ execute conn "INSERT INTO messages(message) VALUES (?)" (Only msg)
          return ProcessingSucceeded
        )
      ]

main :: IO ()
main = app