-- ------------------------------------------------------------
--
-- input functions
-- implemented as filer
--
-- Version : $Id$

module Text.XML.HXT.Parser.XmlInput
    ( getXmlContents
    , getXmlEntityContents
    , getUrlContents
    , getContentLength
    , guessDocEncoding
    , runInLocalURIContext
    , getBaseURI
    , setBaseURI
    , getAbsolutURI
    , isStandaloneDocument
    )

where

import Text.XML.HXT.DOM.XmlTree

import Text.XML.HXT.DOM.XmlState

import Text.XML.HXT.Parser.DefaultURI
    ( setDefaultURI
    )

import Text.XML.HXT.Parser.XmlParser
    ( parseXmlDocEncodingSpec
    , parseXmlEntityEncodingSpec
    )

import Text.XML.HXT.DOM.Unicode
    ( getEncodingFct
    )

import Text.XML.HXT.Parser.XmlOutput
    ( traceTree
    , traceSource
    , traceMsg
    )

import Text.XML.HXT.Parser.ProtocolHandler
    ( getProtocolHandler
    )

-- ------------------------------------------------------------
--
-- URI manipulation

import Network.URI
    ( URI
    , parseURI
    , relativeTo
    , scheme
    )

-- ------------------------------------------------------------
--
-- utilities

import Data.Maybe

-- ------------------------------------------------------------
--
-- filter for reading the content
-- input: a root node with arguments in tag attribute list
-- and without any children.

-- attribute a_source   ("source")   for input file or uri
--
-- attribute a_encoding ("encoding") for encoding scheme
--
-- attribute a_proxy    ("proxy")    for proxy tob be used in http access

getXmlContents'		:: XmlFilter -> XmlStateFilter a
getXmlContents' parseEncodingSpec
    = getContent'
      `whenM` isRoot
      where
      getContent' t'
	  = ( liftMf (setStatus c_ok "getXmlContents")
	      .>>
	      getUrlContents
	      .>>
	      liftF parseEncodingSpec
	      .>>
	      guessDocEncoding
	      .>>
	      traceMsg 1 ("getXmlContents: content read and decoded from " ++ show input')
	      .>>
	      traceTree
	      .>>
	      traceSource
	    ) t'
	    where
	    input' = valueOf a_source t'

-- |
-- filter for reading the content of a XML document
--
-- input is a root node with the source as an attibute
-- the text is read, the encoding scheme is parsed and selected
-- and the input is translated into the internal UTF-8 string representation

getXmlContents		:: XmlStateFilter a
getXmlContents
    = getXmlContents' parseXmlDocEncodingSpec
      .>>
      setBaseURIFilter
      .>>
      setStandAloneFilter

-- |
-- filter for reading the content of an external XML entity
--
--
-- see also : 'getXmlContents'

getXmlEntityContents	:: XmlStateFilter a
getXmlEntityContents
    = getXmlContents' parseXmlEntityEncodingSpec
      .>>
      setBaseURIFilter

-- ------------------------------------------------------------

setBaseURIFilter	:: XmlStateFilter a
setBaseURIFilter
    = performAction (\ t -> setBaseURI (valueOf transferURI t))
      `whenM` isRoot

-- |
-- filter command for saving and restoring
-- the base URI
--
--    * 1.parameter f :  the filter that possible changes the base URI
--
--
--    - returns : a filter with the same effect as f, that restores the base URI after application of f

runInLocalURIContext		:: XmlStateFilter a -> XmlStateFilter a
runInLocalURIContext f t
    = do
      oldContext <- getBaseURI
      trace 2 ("runInLocalURIContext: save base URI " ++ show oldContext)
      res <- f t
      setBaseURI oldContext
      trace 2 ("runInLocalURIContext: restore base URI " ++ show oldContext)
      return res

-- ------------------------------------------------------------
-- |
-- guessEncoding uses encoding attribute and content
-- to determine the encoding scheme.
--
-- it's assumed that an encoding spec has been tried to parse before guessing the encoding.
--
-- UTF-8 is the default encoding
--
-- other supported encodings are ISO-8859-1 (also known as ISO-Latin-1),
-- US-ASCII, UTF-16 or ISO-10646-UCS-2, UTF-16BE, UTF-16LE

guessDocEncoding	:: XmlStateFilter a
guessDocEncoding
    = addDocEncoding
      `whenM` isRoot
    where
    addDocEncoding n'
	= do
	  trace 2 ( "guessDocEncoding: encoding is " ++ show guess)
	  ( encFilter (getEncodingFct guess)
	    .>>
	    liftMf (addAttr transferEncoding guess) ) n'
	  where
	  guess	:: String
	  guess	= head . filter (not . null)
		  $ [ (guessEncoding . showXText . getChildren) n'
		    , valueOf transferEncoding n'
		    , valueOf a_encoding n'
		    , utf8
		    ]
	  encFilter (Just fct)
	      = liftMf (processChildren (modifyText (normalizeNL . fct)))
	  encFilter Nothing
	      = addFatal ("encoding scheme not supported: " ++ show guess)

	  
-- ------------------------------------------------------------
--
-- White Space (2.3)
-- end of line handling (2.11)
-- \#x0D and \#x0D\#x0A are mapped to \#x0A

normalizeNL	:: String -> String
normalizeNL ('\r' : '\n' : rest)	= '\n' : normalizeNL rest
normalizeNL ('\r' : rest)		= '\n' : normalizeNL rest
normalizeNL (c : rest)			= c    : normalizeNL rest
normalizeNL []				= []

-- ------------------------------------------------------------

getDefaultURI	:: XState state String
getDefaultURI
    = do
      uri <- getSysParam transferDefaultURI
      if null uri
	 then do
	      setDefaultURI
	      getDefaultURI
	 else return uri

-- |
-- set the base URI, all other URIs are handled relative to this base URI
--
-- the default base URI is @file:\/\/localhost\/&lt;current-working-dir&gt;\/@
--
-- see also : 'getBaseURI'

setBaseURI	:: String -> XState state ()
setBaseURI str
    = do
      trace 2 ("setBaseURI: new base URI: " ++ show str)
      setSysParam transferURI str

-- |
-- read the current base URI
--
-- see also : 'setBaseURI'

getBaseURI	:: XState state String
getBaseURI
    = do
      uri <- getSysParam transferURI
      if null uri
	 then do
	      res <- getDefaultURI
	      setBaseURI res
	      getBaseURI
	 else return uri

-- |
-- transform an URI into an absolut URI using the current base URI
--
--
--    * 1.parameter uri :  the URI as string
--
--
--    - returns : the absolut URI as string or \"\" in case of an error

getAbsolutURI	:: String -> XState state String
getAbsolutURI uri
    = do
      baseUri <- getBaseURI
      return $ expandURI uri baseUri

expandURI	:: String -> String -> String
expandURI uri base
    = fromMaybe "" $ expand
    where
    expand = do
	     base' <- parseURI base
	     uri'  <- parseURI uri
	     abs'  <- relativeTo uri' base'
	     return $ show abs'

-- ------------------------------------------------------------

setStandAloneFilter	:: XmlStateFilter a
setStandAloneFilter
    = performAction setStandAlone
      where
      setStandAlone t
	  = do
	    if null standalone
	       then return ()
	       else do
		    trace 2 ("setStandAloneFilter: standalone=" ++ show standaloneVal)
		    setSysParam a_standalone standaloneVal
	    where
	    standalone	= getValue a_standalone t
	    standaloneVal	= showXText standalone

-- |
-- predicate for testing the standalone document attribute

isStandaloneDocument	:: XState state Bool
isStandaloneDocument
    = do
      val <- getSysParam a_standalone
      return (val == "yes")

-- ------------------------------------------------------------

-- |
-- the hard io operations
--
-- for reading a file or accessing a document via http
-- input must be a root node with a @source@ attribute specifying the URI

getUrlContents	:: XmlStateFilter a
getUrlContents
    =  getCont
      `whenM` isRoot
    where
    getCont n'
	= do
	  trace 1 ("getUrlContent: reading " ++ show src)
	  uri <- getAbsolutURI src
	  if null uri
	     then urlErr ( "illegal URI for input: " ++ show src )
	     else let
		  uri'     = fromJust $ parseURI uri
		  proto    = scheme uri'
		  handler  = getProtocolHandler proto
		  in
		  ( liftMf (addAttr transferProtocol proto
			   .>
			   addAttr transferURI uri
			  )
		    .>>
		    handler uri'
		  ) $ n'
	where
	src        = valueOf a_source n'
	urlErr msg = addFatal msg n'

-- ------------------------------------------------------------

-- |
-- compute the length of the data for a document read previously
-- by a call of 'getUrlContents. The result is stored as an attribute
-- value in the document root node. the attribute name is 'a_contentLength'

getContentLength	:: XmlFilter
getContentLength
    = addAttrl contentLengthAttr
      `when` isRoot
      where
      http_contentLength	= httpPrefix ++ "Content-Length"

      contentLengthAttr		:: XmlFilter
      contentLengthAttr t
	  = choice [ hasAttr a_contentLength
		     :-> none
		   , hasAttr http_contentLength
		     :-> mkXAttr a_contentLength (getValue http_contentLength)
		   , this
                     :-> mkXAttr a_contentLength getLength
		   ] t

      getLength			:: XmlFilter
      getLength t
	  = xtext (show . length . xshow . getChildren $ t)


-- ------------------------------------------------------------
--
-- gues the encoding scheme by looking at the first few characters
--
-- see XML Standard F.1

guessEncoding		:: String -> String

guessEncoding ('\xFF':'\xFE':'\x00':'\x00':_)	= "UCS-4LE"		-- with byte order mark
guessEncoding ('\xFF':'\xFE':_)			= "UTF-16LE"		-- with byte order mark

guessEncoding ('\xFE':'\xFF':'\x00':'\x00':_)	= "UCS-4-3421"		-- with byte order mark
guessEncoding ('\xFE':'\xFF':_)			= "UTF-16BE"		-- with byte order mark

guessEncoding ('\xEF':'\xBB':'\xBF':_)		= utf8			-- with byte order mark

guessEncoding ('\x00':'\x00':'\xFE':'\xFF':_)	= "UCS-4BE"		-- with byte order mark
guessEncoding ('\x00':'\x00':'\xFF':'\xFE':_)	= "UCS-4-2143"		-- with byte order mark

guessEncoding ('\x00':'\x00':'\x00':'\x3C':_)	= "UCS-4BE"		-- "<" of "<?xml"
guessEncoding ('\x3C':'\x00':'\x00':'\x00':_)	= "UCS-4LE"		-- "<" of "<?xml"
guessEncoding ('\x00':'\x00':'\x3C':'\x00':_)	= "UCS-4-2143"		-- "<" of "<?xml"
guessEncoding ('\x00':'\x3C':'\x00':'\x00':_)	= "UCS-4-3412"		-- "<" of "<?xml"

guessEncoding ('\x00':'\x3C':'\x00':'\x3F':_)	= "UTF-16BE"		-- "<?" of "<?xml"
guessEncoding ('\x3C':'\x00':'\x3F':'\x00':_)	= "UTF-16LE"		-- "<?" of "<?xml"

guessEncoding ('\x4C':'\x6F':'\xA7':'\x94':_)	= "EBCDIC"		-- "<?xm" of "<?xml"

guessEncoding _					= ""			-- no guess

-- ------------------------------------------------------------
