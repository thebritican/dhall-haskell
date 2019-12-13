{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Control.Applicative            ( (<|>)
                                                , optional
                                                )
import           Control.Exception              ( SomeException )
import           Data.Aeson                     ( Value )
import           Data.Monoid                    ( (<>) )
import           Data.Version                   ( showVersion )
import           Options.Applicative            ( Parser
                                                , ParserInfo
                                                )

import qualified Control.Exception
import qualified Data.Aeson
import qualified Data.Aeson.Encode.Pretty
import qualified Data.ByteString.Lazy
import qualified Data.Text.IO                  as Text.IO
import qualified Dhall
import qualified GHC.IO.Encoding
import qualified Options.Applicative           as Options
import qualified System.Exit
import qualified System.IO

data Options
    = Options
        { explain                   :: Bool
        , omission                  :: Value -> Value
        , file                      :: Maybe FilePath
        , output                    :: Maybe FilePath
        }
    | Version

parseOptions :: Parser Options
parseOptions =
  (   Options
    <$> parseExplain
    <*> parseApproximateSpecialDoubles
    <*> optional parseFile
    <*> optional parseOutput
    )
    <|> parseVersion
 where
  parseExplain = Options.switch
    (Options.long "explain" <> Options.help "Explain error messages in detail")

  parseVersion = Options.flag'
    Version
    (Options.long "version" <> Options.help "Display version")

  parseFile = Options.strOption
    (  Options.long "file"
    <> Options.help "Read expression from a file instead of standard input"
    <> Options.metavar "FILE"
    )

  parseOutput = Options.strOption
    (  Options.long "output"
    <> Options.help "Write GraphQL SDL to a file instead of standard output"
    <> Options.metavar "FILE"
    )

parserInfo :: ParserInfo Options
parserInfo = Options.info
  (Options.helper <*> parseOptions)
  (Options.fullDesc <> Options.progDesc "Compile Dhall to GraphQL SDL")

main :: IO ()
main = do
  GHC.IO.Encoding.setLocaleEncoding GHC.IO.Encoding.utf8

  options <- Options.execParser parserInfo

  case options of
    Version -> do
      putStrLn (showVersion Meta.version)

    Options {..} -> do
      handle $ do
        let
          config = Data.Aeson.Encode.Pretty.Config
            { Data.Aeson.Encode.Pretty.confIndent          =
              Data.Aeson.Encode.Pretty.Spaces 2
            , Data.Aeson.Encode.Pretty.confCompare         = compare
            , Data.Aeson.Encode.Pretty.confNumFormat       =
              Data.Aeson.Encode.Pretty.Generic
            , Data.Aeson.Encode.Pretty.confTrailingNewline = False
            }
        let explaining = if explain then Dhall.detailed else id

        text <- case file of
          Nothing   -> Text.IO.getContents
          Just path -> Text.IO.readFile path

        graphql <- omission <$> explaining
          (Dhall.GraphQL.codeToValue conversion specialDoubleMode file text)

        let write = case output of
              Nothing    -> Data.ByteString.Lazy.putStr
              Just file_ -> Data.ByteString.Lazy.writeFile file_

        write (encode graphql <> "\n")

handle :: IO a -> IO a
handle = Control.Exception.handle handler
 where
  handler :: SomeException -> IO a
  handler e = do
    System.IO.hPutStrLn System.IO.stderr ""
    System.IO.hPrint System.IO.stderr e
    System.Exit.exitFailure
