{-| 
Module      :  $Header$
Copyright   :  (c) Martin K�hl, Christian Maeder, Uni Bremen 2002-2005
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

   Datatypes for options that hets understands.
   Useful functions to parse and check user-provided values.
-}

{- Maybe TODO:
    -- an Error should be raised when more than one OutDir were specified,
       or when the OutDir wasn't approved sane
-}

module Driver.Options 
    ( defaultHetcatsOpts
    , showDiags
    , showDiags1
    , guess
    , existsAnSource
    , checkRecentEnv
    , doIfVerbose
    , putIfVerbose
    , hetcatsOpts
    , HetcatsOpts(..)
    , GuiType(..)
    , InType(..)
    , AnaType(..)
    , RawOpt(..)
    , OutType(..)
    , WebType(..)
    , HetOutFormat(..)
    , HetOutType(..)
    , PrettyType(..)
    ) where

import Driver.Version
import Common.Utils
import Common.Result
import Common.Amalgamate(CASLAmalgOpt(..))

import System.Directory
import System.Exit

import Data.List
import Control.Monad (filterM)

import System.Console.GetOpt

bracket :: String -> String
bracket s = "[" ++ s ++ "]" 

-- use the same strings for parsing and printing!
verboseS, intypeS, outtypesS, rawS, skipS, structS,
     guiS, onlyGuiS, libdirS, outdirS, amalgS, webS :: String

verboseS = "verbose"
intypeS = "input-type"
outtypesS = "output-types"
rawS = "raw"
skipS = "just-parse"
structS = "just-structured"
guiS = "gui"
onlyGuiS = "only-gui"
libdirS = "hets-libdir"
outdirS = "output-dir"
amalgS = "casl-amalg"
webS = "web"

asciiS, latexS, textS, texS :: String
asciiS = "ascii"
latexS = "latex"
textS = "text"
texS = "tex"

genTermS, treeS, bafS, astS :: String
genTermS = "gen_trm"
treeS = "tree."
bafS = ".baf"
astS = "ast"

graphS, ppS, envS, naxS, dS :: String
graphS = "graph."
ppS = "pp."
envS = "env"
naxS = ".nax"
dS = "."

showOpt :: String -> String 
showOpt s = if null s then "" else " --" ++ s

showEqOpt :: String -> String -> String 
showEqOpt k s = if null s then "" else showOpt k ++ "=" ++ s 

-- main Datatypes --

-- | 'HetcatsOpts' is a record of all options received from the command line
data HetcatsOpts =        -- for comments see usage info
    HcOpt { analysis :: AnaType    
          , gui      :: GuiType    
          , infiles  :: [FilePath] -- files to be read
          , intype   :: InType     
          , libdir   :: FilePath   
          , outdir   :: FilePath   
          , outtypes :: [OutType]  
          , rawopts  :: [RawOpt]   
          , verbose  :: Int        
	  , defLogic :: String     
	  , web      :: WebType    
          , outputToStdout :: Bool    -- flag: output diagnostic messages?
	  , caslAmalg :: [CASLAmalgOpt] 
          }

instance Show HetcatsOpts where
    show opts =  showEqOpt verboseS (show $ verbose opts)
                ++ show (gui opts)
                ++ show (analysis opts)
                ++ show (web opts)
                ++ showEqOpt libdirS (libdir opts)
                ++ showEqOpt intypeS (show $ intype opts)
                ++ showEqOpt outdirS (outdir opts)
                ++ showEqOpt outtypesS (showOutTypes $ outtypes opts)
                ++ showRaw (rawopts opts)
                ++ showEqOpt amalgS ( tail $ init $ show $ 
                                      case caslAmalg opts of
                                      [] -> [NoAnalysis]
                                      l -> l)
                ++ " " ++ showInFiles (infiles opts)
        where
        showInFiles  = joinWith ' '
        showOutTypes = joinWith ',' . map show
        showRaw = joinWith ' ' . map show

-- | 'makeOpts' includes a parsed Flag in a set of HetcatsOpts
makeOpts :: HetcatsOpts -> Flag -> HetcatsOpts
makeOpts opts (Analysis x) = opts { analysis = x }
makeOpts opts (Gui x)      = opts { gui = x }
makeOpts opts (InType x)   = opts { intype = x }
makeOpts opts (LibDir x)   = opts { libdir = x }
makeOpts opts (OutDir x)   = opts { outdir = x }
makeOpts opts (OutTypes x) = opts { outtypes = x }
makeOpts opts (Raw x)      = opts { rawopts = x }
makeOpts opts (Web x)      = opts { web = x }
makeOpts opts (Verbose x)  = opts { verbose = x }
makeOpts opts (DefaultLogic x) = opts { defLogic = x }
makeOpts opts (CASLAmalg x) = opts { caslAmalg = x }
makeOpts opts Quiet         = opts { verbose = 0 }
makeOpts opts Help          = opts -- skipped
makeOpts opts Version       = opts -- skipped

-- | 'defaultHetcatsOpts' defines the default HetcatsOpts, which are used as
-- basic values when the user specifies nothing else
defaultHetcatsOpts :: HetcatsOpts
defaultHetcatsOpts = 
    HcOpt { analysis = Basic
          , gui      = Not
	  , web      = NoWeb
          , infiles  = []
          , intype   = GuessIn
          , libdir   = ""
          , outdir   = ""
          , outtypes = [defaultOutType]
          -- better default options, but not implemented yet:
          --, outtypes = [HetCASLOut OutASTree OutXml]
          , rawopts  = []
	  , defLogic = "CASL"
          , verbose  = 1
          , outputToStdout = True
	  , caslAmalg = [Cell]
          }

defaultOutType :: OutType
defaultOutType = HetCASLOut OutASTree OutAscii

-- | every 'Flag' describes an option (see usage info)
data Flag = Analysis AnaType     
          | Gui      GuiType     
          | Help                 
          | InType   InType      
          | LibDir   FilePath    
          | OutDir   FilePath    
          | OutTypes [OutType]   
          | Quiet                
          | Raw      [RawOpt]    
          | Verbose  Int         
          | Version              
	  | Web      WebType     
	  | DefaultLogic String  
	  | CASLAmalg [CASLAmalgOpt] 

-- | 'AnaType' describes the type of analysis to be performed
data AnaType = Basic | Structured | Skip

instance Show AnaType where
    show a = case a of
             Basic -> ""
             Structured -> showOpt structS
             Skip -> showOpt skipS

-- | 'GuiType' determines if we want the GUI shown
data GuiType = Only | Also | Not

instance Show GuiType where
    show g = case g of
             Only -> showOpt onlyGuiS
             Also -> showOpt guiS
             Not  -> ""

-- | 'InType' describes the type of input the infile contains
data InType = ATermIn ATType | ASTreeIn ATType | CASLIn | WebIn | HetCASLIn 
            | HaskellIn | GuessIn

instance Show InType where
    show i = case i of
             ATermIn at -> genTermS ++ show at
             ASTreeIn at -> astS ++ show at
             CASLIn -> "casl"
             WebIn -> "web"
             HetCASLIn -> "het"
             HaskellIn -> "hs"
             GuessIn -> ""

-- maybe this optional tree prefix can be omitted
instance Read InType where 
    readsPrec _ s = let f = filter ( \ o -> (case o of 
                                 ATermIn _ -> isPrefixOf (treeS ++ show o) s
                                 _ -> False) || isPrefixOf (show o) s) 
                            (plainInTypes ++ aInTypes)
                        in case f of 
                           [] -> []
                           t : _ -> [(t, drop (length (show t) +
                                             case t of 
                                             ATermIn _ -> if isPrefixOf treeS s
                                               then length treeS else 0
                                             _ -> 0) s)]

-- | 'ATType' describes distinct types of ATerms
data ATType = BAF | NonBAF

instance Show ATType where
    show a = case a of BAF -> bafS
                       NonBAF -> ""

plainInTypes :: [InType]
plainInTypes = [CASLIn, HetCASLIn, HaskellIn, WebIn]

aInTypes :: [InType]
aInTypes = [ f x | f <- [ASTreeIn, ATermIn], x <- [BAF, NonBAF] ]

-- | 'OutType' describes the type of outputs that we want to generate
data OutType = PrettyOut PrettyType 
             | HetCASLOut HetOutType HetOutFormat
             | GraphOut GraphType
	     | EnvOut

instance Show OutType where
    show o = case o of
             PrettyOut p -> ppS ++ show p
             HetCASLOut h f -> show h ++ dS ++ show f
             GraphOut f -> graphS ++ show f
             EnvOut -> envS

instance Read OutType where
    readsPrec  _ s = if isPrefixOf ppS s then 
        case reads $ drop (length ppS) s of
                 [(p, r)] -> [(PrettyOut p, r)]
                 _ -> hetsError (s ++ " expected one of " ++ show prettyList)
        else if isPrefixOf graphS s then 
        case reads $ drop (length graphS) s of
                 [(t, r)] -> [(GraphOut t, r)]
                 _ -> hetsError (s ++ " expected one of " ++ show graphList)
        else if isPrefixOf envS s then
             [(EnvOut, drop (length envS) s)]
        else [(HetCASLOut h f, u) | (h, d : t) <- reads s, 
              d == '.' , (f, u) <- reads t]

-- | 'PrettyType' describes the type of output we want the pretty-printer 
-- to generate
data PrettyType = PrettyAscii | PrettyLatex | PrettyHtml

instance Show PrettyType where
    show p = case p of
             PrettyAscii -> "het"
             PrettyLatex -> "tex"
             PrettyHtml -> "html"

instance Read PrettyType where
    readsPrec _ = readShow prettyList

prettyList :: [PrettyType]
prettyList = [PrettyAscii,  PrettyLatex, PrettyHtml]

-- | 'HetOutType' describes the type of Output we want Hets to create
data HetOutType = OutASTree | OutDGraph Flattening Bool

instance Show HetOutType where
    show h = case h of 
             OutASTree -> astS
             OutDGraph f b -> show f ++ "dg" ++ if b then naxS else ""

instance Read HetOutType where
    readsPrec _ s = if isPrefixOf astS s then 
                    [(OutASTree, drop (length astS) s)] 
                    else case readShow outTypeList s of
                    l@[(OutDGraph f _, r)] -> if isPrefixOf naxS r then
                             [(OutDGraph f True, drop (length naxS) r)]
                             else l
                    _ -> hetsError (s ++ " is not a valid OTYPE")

outTypeList :: [HetOutType]
outTypeList = [ OutDGraph f False | f <- [ Flattened, HidingOutside, Full]]

-- | 'Flattening' describes how flat the Earth really is (TODO: add comment)
data Flattening = Flattened | HidingOutside | Full

instance Show Flattening where
    show f = case f of 
             Flattened -> "f"
             HidingOutside -> "h"
             Full -> ""

-- | 'HetOutFormat' describes the format of Output that HetCASL shall create
data HetOutFormat = OutAscii | OutTerm | OutTaf | OutHtml | OutXml

instance Show HetOutFormat where
    show f = case f of
             OutAscii -> "het"
             OutTerm -> "trm"
             OutTaf -> "taf"
             OutHtml -> "html"
             OutXml -> "xml"

instance Read HetOutFormat where
    readsPrec _ = readShow formatList

formatList :: [HetOutFormat]
formatList = [OutAscii, OutTerm, OutTaf, OutHtml, OutXml]

-- | 'GraphType' describes the type of Graph that we want generated
data GraphType = Dot | PostScript | Davinci

instance Show GraphType where
    show g = case g of
             Dot -> "dot"
             PostScript -> "ps"
             Davinci -> "davinci"

instance Read GraphType where
    readsPrec _ = readShow graphList

graphList :: [GraphType]
graphList = [Dot, PostScript, Davinci]

-- | 'WebType'
data WebType = WebType | NoWeb  -- compare with WebIn?!

instance Show WebType where
    show w = case w of
             WebType -> showOpt webS
             NoWeb -> ""

-- | 'RawOpt' describes the options we want to be passed to the Pretty-Printer
data RawOpt = RawAscii String | RawLatex String

instance Show RawOpt where
    show r = case r of
             RawAscii s -> showRawOpt asciiS s
             RawLatex s -> showRawOpt latexS s
             where showRawOpt f = showEqOpt (rawS ++ "=" ++ f)

instance Show CASLAmalgOpt where
    show o = case o of 
             Sharing -> "sharing"
             ColimitThinness -> "colimit-thinness"
             Cell -> "cell"
             NoAnalysis -> "none"

instance Read CASLAmalgOpt where
    readsPrec _ = readShow caslAmalgOpts

readShow :: Show a => [a] -> ReadS a
readShow l s = case find ( \ o -> isPrefixOf (show o) s) l of
               Nothing -> []
               Just t -> [(t, drop (length $ show t) s)]
             
-- | possible CASL amalgamability options
caslAmalgOpts :: [CASLAmalgOpt]
caslAmalgOpts = [NoAnalysis, Sharing, Cell, ColimitThinness]

-- | 'options' describes all available options and is used to generate usage 
-- information
options :: [OptDescr Flag]
options = 
    [ Option ['v'] [verboseS] (OptArg parseVerbosity "Int")
      "set verbosity level, -v1 is the default"
    , Option ['q'] ["quiet"] (NoArg Quiet)
      "same as -v0, no output at all to stdout"
    , Option ['V'] ["version"] (NoArg Version)
      "print version number and exit"
    , Option ['h'] ["help", "usage"] (NoArg Help)
      "print usage information and exit"
    , Option ['g'] [guiS] (NoArg (Gui Also))
      "show graphical output in a GUI window"
    , Option ['G'] [onlyGuiS] (NoArg $ Gui Only)
      "like -g but write no output files"
    , Option ['w'] [webS] (NoArg (Web WebType))
      "show web interface"
    , Option ['p'] [skipS]  (NoArg $ Analysis Skip)
      "skip static analysis, just parse"
    , Option ['s'] [structS]  (NoArg $ Analysis Structured)
      "skip basic, just do structured analysis"
    , Option ['l'] ["logic"] (ReqArg DefaultLogic "LOGIC")
      "choose initial logic, the default is CASL"
    , Option ['L'] [libdirS]  (ReqArg LibDir "DIR")
      "source directory of [Het]CASL libraries"
    , Option ['i'] [intypeS]  (ReqArg parseInType "ITYPE")
      ("input file type can be one of:" ++ crS ++ joinBar 
       (map show plainInTypes ++
        map (++ bracket bafS) [astS, bracket treeS ++ genTermS]))
    , Option ['O'] [outdirS]  (ReqArg OutDir "DIR")
      "destination directory for output files"
    , Option ['o'] [outtypesS] (ReqArg parseOutTypes "OTYPES")
      ("output file types, default " ++ show defaultOutType ++ "," ++ crS ++
       listS ++ crS ++ bS ++ envS ++ crS ++ bS ++
       ppS ++ joinBar (map show prettyList) ++ crS ++ bS ++
       graphS ++ joinBar (map show graphList) ++ crS ++ bS ++
       astS ++ formS ++ crS ++ bS ++ 
       joinBar (map show outTypeList) ++ bracket naxS ++ formS)
    , Option ['r'] [rawS] (ReqArg parseRawOpts "RAW")
      ("raw options for pretty printing" ++ crS ++ "RAW is " 
       ++ joinBar [asciiS, textS, latexS, texS]
       ++ "=STRING where " ++ crS ++ 
       "STRING is passed to the appropriate printer")
    , Option ['a'] [amalgS] (ReqArg parseCASLAmalg "ANALYSIS")
      ("CASL amalgamability analysis options" ++ crS ++ listS ++ 
       crS ++ joinBar (map show caslAmalgOpts))
    ] where listS = 
              "is a comma-separated list without blanks of one or more from:"
            crS = "\n\t\t"
            bS = "| "
            joinBar l = "(" ++ joinWith '|' l ++ ")"
            formS = dS ++ joinBar (map show formatList)

-- parser functions returning Flags --

-- | 'parseVerbosity' parses a 'Verbose' Flag from user input
parseVerbosity :: (Maybe String) -> Flag
parseVerbosity Nothing = Verbose 2
parseVerbosity (Just s)
    = case reads s of
                   [(i,"")] -> Verbose i
                   _        -> hetsError (s ++ " is not a valid INT")

-- | intypes useable for downloads
downloadExtensions :: [String]
downloadExtensions = map show plainInTypes

-- |
-- checks if a source file for the given base  exists
existsAnSource :: FilePath -> IO (Maybe FilePath)
existsAnSource base2 = 
       do
       let names = map (base2++) ("":(map (dS ++) downloadExtensions))
       -- look for the first existing file
       existFlags <- sequence (map doesFileExist names)
       return (find fst (zip existFlags names) >>= (return . snd))

-- | 
-- gets two Paths and checks if the first file is more recent than the
-- second one
checkRecentEnv :: FilePath -> FilePath -> IO Bool
checkRecentEnv fp1 base2 = 
   do fp1_exists <- doesFileExist fp1
      if not fp1_exists then return False 
       else do
        maybe_source_file <- existsAnSource base2
        maybe (return False) 
	     (\ fp2 ->     do fp1_time <- getModificationTime fp1
	                      fp2_time <- getModificationTime fp2
		              return (fp1_time > fp2_time))
	     maybe_source_file

-- | 'parseInType' parses an 'InType' Flag from user input
parseInType :: String -> Flag
parseInType = InType . parseInType1


-- | 'parseInType1' parses an 'InType' Flag from a String
parseInType1 :: String -> InType
parseInType1 str = 
  case reads str of 
    [(t, "")] -> t
    _ -> hetsError (str ++ " is not a valid ITYPE")
      {- the mere typo read instead of reads caused the runtime error:
         Fail: Prelude.read: no parse -}

-- 'parseOutTypes' parses an 'OutTypes' Flag from user input
parseOutTypes :: String -> Flag
parseOutTypes str = case reads $ bracket str of
    [(l, "")] -> OutTypes l
    _ -> hetsError (str ++ " is not a valid OTYPES")
  
-- | 'parseRawOpts' parses a 'Raw' Flag from user input
parseRawOpts :: String -> Flag
parseRawOpts s =
    let (prefix, string) = break (== '=') s
        parsePrefix p = if p `elem` [asciiS, textS] then RawAscii
                        else if p `elem` [latexS, texS] then RawLatex
                        else hetsError (s ++ " is not a valid RAW String")
    in Raw [(parsePrefix prefix) (drop 1 string)]

-- | guesses the InType
guess :: String -> InType -> InType
guess file GuessIn = guessInType file
guess _file itype  = itype

-- | 'guessInType' parses an 'InType' from the FilePath to our 'InFile'
guessInType :: FilePath -> InType
guessInType file = 
    case fileparse (map show (plainInTypes ++ aInTypes) ++
                    map ( \ t -> treeS ++ show t) 
                    [ ATermIn x | x <- [BAF, NonBAF]])
         file of
      (_,_,Just suf) -> parseInType1 suf
      (_,_,Nothing)  -> hetsError $
                        "InType of " ++ file ++ " unclear, please specify"


-- | 'parseCASLAmalg' parses CASL amalgamability options
parseCASLAmalg :: String -> Flag
parseCASLAmalg str = 
    case reads $ bracket str of
    [(l, "")] -> CASLAmalg $ filter ( \ o -> case o of 
                                      NoAnalysis -> False 
                                      _ -> True ) l
    _ -> hetsError (str ++ 
                    " is not a valid CASL amalgamability analysis option list")

-- main functions --

-- | 'hetcatsOpts' parses sensible HetcatsOpts from ARGV
hetcatsOpts :: [String] -> IO HetcatsOpts
hetcatsOpts argv =
  let argv' = filter (not . isUni) argv
      isUni s = take 5 s == "--uni"
   in case (getOpt Permute options argv') of
        (opts,non_opts,[]) ->
            do flags <- checkFlags opts
               infs  <- checkInFiles non_opts
               hcOpts <- return $ 
                         foldr (flip makeOpts) defaultHetcatsOpts flags
	       let hcOpts' = hcOpts { infiles = infs }
               seq (length $ show hcOpts') $ return $ hcOpts' 
        (_,_,errs) -> hetsError (concat errs)

-- | 'checkFlags' checks all parsed Flags for sanity
checkFlags :: [Flag] -> IO [Flag]
checkFlags fs =
    let collectFlags = (collectOutDirs
                        . collectOutTypes
                        . collectVerbosity
                        . collectRawOpts
                        -- collect some more here?
                   )
    in do if not $ null [ () | Help <- fs]
             then do putStrLn hetsUsage
                     exitWith ExitSuccess
             else return [] -- fall through
          if not $ null [ () | Version <- fs] 
             then do putStrLn ("version of hets: " ++ hetcats_version)
                     exitWith ExitSuccess
             else return [] -- fall through
          fs' <- collectFlags fs
          return fs'

-- | 'checkInFiles' checks all given InFiles for sanity
checkInFiles :: [String] -> IO [FilePath]
checkInFiles fs = 
    do ifs <- filterM checkInFile fs
       case ifs of
                []  -> return (hetsError "No valid input file specified")
                xs  -> return xs


-- auxiliary functions: FileSystem interaction --

-- | 'checkInFile' checks a single InFile for sanity
checkInFile :: FilePath -> IO Bool
checkInFile file =
    do exists <- doesFileExist file
       perms  <- catch (getPermissions file) (\_ -> return noPerms)
       return (exists && (readable perms))

-- | 'checkOutDirs' checks a list of OutDir for sanity
checkOutDirs :: [Flag] -> IO [Flag]
checkOutDirs fs = 
    do ods <- ((filterM checkOutDir) 
               . (map (\(OutDir x) -> x))) fs
       if null ods
          then return []
          else return $ [OutDir $ head ods]

-- | 'checkOutDir' checks a single OutDir for sanity
checkOutDir :: String -> IO Bool
checkOutDir file = 
    do exists <- doesDirectoryExist file
       perms  <- catch (getPermissions file) (\_ -> return noPerms)
       return (exists && (writable perms))

-- Nil Permissions. Returned, if an Error occurred in FS-Interaction
noPerms :: Permissions
noPerms = Permissions { readable = False
                      , writable = False
                      , executable = False
                      , searchable = False
                      }

-- auxiliary functions: collect flags -- 

collectOutDirs :: [Flag] -> IO [Flag]
collectOutDirs fs =
    let (ods,fs') = partition isOutDir fs
        isOutDir (OutDir _) = True
        isOutDir _          = False
    in do ods' <- checkOutDirs ods
          return $ ods' ++ fs'

collectVerbosity :: [Flag] -> [Flag]
collectVerbosity fs =
    let (vs,fs') = partition isVerb fs
        verbosity = (sum . map (\(Verbose x) -> x)) vs
        isVerb (Verbose _) = True
        isVerb _           = False
        vfs = Verbose verbosity : fs'
    in if not $ null [() | Quiet <- fs'] then Verbose 0 : fs' else
       if null vs then Verbose 1 : fs' else vfs

collectOutTypes :: [Flag] -> [Flag]
collectOutTypes fs =
    let (ots,fs') = partition isOType fs
        isOType (OutTypes _) = True
        isOType _            = False
        otypes = foldl concatOTypes [] ots
        concatOTypes = (\os (OutTypes ot) -> os ++ ot)
    in if null otypes || not (null [() | Gui Only <- fs'])
        then fs'
        else ((OutTypes otypes):fs')

collectRawOpts :: [Flag] -> [Flag]
collectRawOpts fs =
    let (rfs,fs') = partition isRawOpt fs
        isRawOpt (Raw _) = True
        isRawOpt _       = False
        raws = foldl concatRawOpts [] rfs
        concatRawOpts = (\os (Raw ot) -> os ++ ot)
    in if (null raws) then fs' else ((Raw raws):fs')


-- auxiliary functions: error messages --

-- | 'hetsError' is a generic Error messaging function that prints the Error
-- and usage information, if the user caused the Error
hetsError :: String -> a
hetsError errorString = error (errorString ++ "\n" ++ hetsUsage)

-- | 'hetsUsage' generates usage information for the commandline
hetsUsage :: String
hetsUsage = usageInfo header options
    where header = "Usage: hets [OPTION...] file ... file"

-- | 'putIfVerbose' prints a given String to StdOut when the given HetcatsOpts' 
-- Verbosity exceeds the given level
putIfVerbose :: HetcatsOpts -> Int -> String -> IO ()
putIfVerbose opts level str = 
    if outputToStdout opts
       then doIfVerbose opts level (putStrLn str)
    else return()

-- | 'doIfVerbose' executes a given function when the given HetcatsOpts' 
-- Verbosity exceeds the given level
doIfVerbose :: HetcatsOpts -> Int -> (IO ()) -> IO ()
doIfVerbose opts level func =
    if (verbose opts) >= level then func
        else return ()

-- | show diagnostic messages (see Result.hs), according to verbosity level
showDiags :: HetcatsOpts -> [Diagnosis] -> IO()
showDiags opts ds = do
    ioresToIO $ showDiags1 opts $ resToIORes $ Result ds Nothing
    return ()

-- | show diagnostic messages (see Result.hs), according to verbosity level
showDiags1 :: HetcatsOpts -> IOResult a -> IOResult a
showDiags1 opts res = do
  if outputToStdout opts
     then do Result ds res' <- ioToIORes $ ioresToIO res 
             ioToIORes $ sequence $ map (putStrLn . show) -- take maxdiags
                       $ filter (relevantDiagKind . diagKind) ds
             case res' of
               Just res'' -> return res''
               Nothing    -> resToIORes $ Result [] Nothing
     else res
  where relevantDiagKind Error = True
        relevantDiagKind Warning = (verbose opts) >= 2
        relevantDiagKind Hint = (verbose opts) >= 4
        relevantDiagKind Debug  = (verbose opts) >= 5
        relevantDiagKind MessageW = False
