{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
-- |
--
-- Methods for working with File resources on Google Drive.
--
-- https://developers.google.com/drive/v2/reference/files
--
-- This module is mostly concerned with creating and updating metadata. See
-- @"Network.Google.Drive.Upload"@ for uploading content.
--
module Network.Google.Drive.File
    (
    -- * File Resource
      File(..)
    , FileId
    , FileData(..)
    , FileTitle

    -- * Building @File@s
    , newFile
    , newFolder
    , setParent
    , setMimeType

    -- * Actions
    , getFile
    , createFile
    , updateFile
    , deleteFile
    , downloadFile

    -- * Utilities
    , isFolder
    , isDownloadable
    , localPath
    ) where

import Network.Google.Api

import Control.Applicative ((<$>), (<*>))
import Control.Monad (mzero, void)
import Data.Aeson
import Data.Maybe (isJust)
import Data.Monoid ((<>))
import Data.Text (Text)
import Data.Time (UTCTime)
import Network.HTTP.Conduit (HttpException(..))
import Network.HTTP.Types (status404)

import qualified Data.Traversable as F
import qualified Data.Text as T

type FileId = Text
type FileTitle = Text

-- | Metadata about Files on your Drive
data FileData = FileData
    { fileTitle :: !FileTitle
    , fileModified :: !UTCTime
    , fileParents :: ![FileId]
    , fileTrashed :: !Bool
    , fileSize :: !(Maybe Int)
    , fileDownloadUrl :: !(Maybe Text)
    , fileMimeType :: !Text
    }

-- | An existing file
data File = File
    { fileId :: FileId
    , fileData :: FileData
    }

instance Eq File where
    a == b = fileId a == fileId b

instance Show File where
    show f = localPath f <> " (" <> T.unpack (fileId f) <> ")"

instance FromJSON FileData where
    parseJSON (Object o) = FileData
        <$> o .: "title"
        <*> o .: "modifiedDate"
        <*> (mapM (.: "id") =<< o .: "parents")
        <*> ((.: "trashed") =<< o .: "labels")
        <*> (fmap read <$> o .:? "fileSize") -- fileSize is a String!
        <*> o .:? "downloadUrl"
        <*> o .: "mimeType"

    parseJSON _ = mzero

instance ToJSON FileData where
    toJSON FileData{..} = object
        [ "title" .= fileTitle
        , "modifiedDate" .= fileModified
        , "parents" .= map (\p -> object ["id" .= p]) fileParents
        , "labels" .= object ["trashed" .= fileTrashed]
        , "mimeType" .= fileMimeType
        ]

instance FromJSON File where
    parseJSON v@(Object o) = File
        <$> o .: "id"
        <*> parseJSON v
    parseJSON _ = mzero

-- | Get a @File@ data by @FileId@
--
-- @\"root\"@ can be used to get information on the Drive itself
--
-- If the API returns 404, this returns @Nothing@
--
getFile :: FileId -> Api (Maybe File)
getFile fid = (Just <$> getJSON (fileUrl fid) [])
    `catchError` handleNotFound

  where
    handleNotFound (HttpError (StatusCodeException s _ _))
        | s == status404 = return Nothing
    handleNotFound e = throwError e

-- | Create a @File@ from @FileData@
createFile :: FileData -> Api File
createFile fd = postJSON (baseUrl <> "/files") [] fd

-- | Update a @File@
updateFile :: FileId -> FileData -> Api File
updateFile fid fd = putJSON (fileUrl $ fid) [] fd

-- | Delete a @File@
deleteFile :: File -> Api ()
deleteFile f = void $ requestLbs (fileUrl $ fileId f) $ setMethod "DELETE"

-- | Download a @File@
--
-- Returns @Nothing@ if the file is not downloadable
--
downloadFile :: File -> DownloadSink a -> Api (Maybe a)
downloadFile f sink = F.forM (fileDownloadUrl $ fileData f) $ \url ->
    getSource (T.unpack url) [] sink

newFile :: FileTitle -> UTCTime -> FileData
newFile title modified = FileData
    { fileTitle = title
    , fileModified = modified
    , fileParents = []
    , fileTrashed = False
    , fileSize = Nothing
    , fileDownloadUrl = Nothing
    , fileMimeType = ""
    }

newFolder :: FileTitle -> UTCTime -> FileData
newFolder title = setMimeType folderMimeType . newFile title

setParent :: File -> FileData -> FileData
setParent p f = f { fileParents = [fileId p] }

setMimeType :: Text -> FileData -> FileData
setMimeType m f = f { fileMimeType = m }

-- | What to name this file if downloaded
--
-- Currently just the @fileTitle@
--
localPath :: File -> FilePath
localPath = T.unpack . fileTitle . fileData

-- | Check if a @File@ is a folder by inspecting its mime-type
isFolder :: File -> Bool
isFolder = (== folderMimeType) . fileMimeType . fileData

-- | Check if a @File@ has content stored in drive
isDownloadable :: File -> Bool
isDownloadable = isJust . fileDownloadUrl . fileData

baseUrl :: URL
baseUrl = "https://www.googleapis.com/drive/v2"

fileUrl :: FileId -> URL
fileUrl fid = baseUrl <> "/files/" <> T.unpack fid

folderMimeType :: Text
folderMimeType = "application/vnd.google-apps.folder"
