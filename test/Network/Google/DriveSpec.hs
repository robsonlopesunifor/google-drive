{-# LANGUAGE OverloadedStrings #-}
module Network.Google.DriveSpec (main, spec) where

import Test.Hspec
import Network.Google.Drive
import Network.Google.OAuth2

import Control.Monad (void)
import Data.Conduit (($$+-))
import Data.Maybe (fromJust, listToMaybe, isJust)
import Control.Applicative ((<$>), (<*>))
import LoadEnv (loadEnv)
import System.Directory (removeFile)
import System.Environment (getEnv)
import System.IO

import qualified Data.Text as T

main :: IO ()
main = hspec spec

-- N.B. requires interaction once, then uses cached OAuth credentials
spec :: Spec
spec = after_ cleanup $ describe "Drive API" $
    it "can upload, list, and delete files" $ do
        writeFile uFilePath fileContents
        fileLength <- getFileSize uFilePath

        token <- getToken

        runApi_ token $ do
            root <- getFile "root"

            folder <- createFolder (fileId root) "google-drive-test"
            file <- newFile (fileId folder) uFilePath
            void $ uploadFile file fileLength $ uploadSourceFile uFilePath

            items <- listFiles $ ParentEq $ fileId folder
            let murl = fileDownloadUrl . fileData =<< listToMaybe items

            liftIO $ murl `shouldSatisfy` isJust

            getSource (T.unpack $ fromJust murl) [] ($$+- sinkFile dFilePath)

            deleteFile file
            deleteFile folder

        content <- readFile dFilePath
        content `shouldBe` fileContents

getToken :: IO OAuth2Token
getToken = do
    loadEnv

    client <- OAuth2Client
        <$> getEnv "CLIENT_ID"
        <*> getEnv "CLIENT_SECRET"

    getAccessToken client driveScopes . Just =<< getEnv "CACHE_FILE"

getFileSize :: FilePath -> IO Int
getFileSize fp = fromIntegral <$> withFile fp ReadMode hFileSize

uFilePath :: FilePath
uFilePath = "test/upload.txt"

dFilePath :: FilePath
dFilePath = "test/downloaded.txt"

fileContents :: String
fileContents = "Uploaded content"

cleanup :: IO ()
cleanup = do
    removeFile uFilePath
    removeFile dFilePath
