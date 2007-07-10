{- |
Module      :  $Header$
Description :  Result monad for accumulating Diagnosis messages
Copyright   :  (c) K. L�ttich, T. Mossakowski, C. Maeder, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

'Result' monad for accumulating 'Diagnosis' messages
               during analysis phases.
-}

module Common.Result where

import Common.Id
import Common.Doc
import Common.DocUtils
import Common.GlobalAnnotations
import Data.List
import Text.ParserCombinators.Parsec.Error
import Text.ParserCombinators.Parsec.Char (char)
import Text.ParserCombinators.Parsec (parse)
import Common.Lexer

-- | severness of diagnostic messages
data DiagKind = Error | Warning | Hint | Debug
              | MessageW -- ^ used for messages in the web interface
                deriving (Eq, Ord, Show)

-- | a diagnostic message with 'Pos'
data Diagnosis = Diag { diagKind :: DiagKind
                      , diagString :: String
                      , diagPos :: Range
                      } deriving Eq

-- | construct a message for a printable item that carries a position
mkDiag :: (PosItem a, Pretty a) => DiagKind -> String -> a -> Diagnosis
mkDiag k s a = let q = text "'" in
    Diag k (s ++ show (space <> q <> pretty a <> q)) $ getRange a

-- | construct a message for a printable item that carries a position
mkNiceDiag :: (PosItem a, Pretty a) => GlobalAnnos
       -> DiagKind -> String -> a -> Diagnosis
mkNiceDiag ga k s a = let q = text "'" in
    Diag k (s ++ show (toText ga $ space <> q <> pretty a <> q)) $ getRange a

-- | check whether a diagnosis is an error
isErrorDiag :: Diagnosis -> Bool
isErrorDiag d = case diagKind d of
                Error -> True
                _ -> False

-- | Check whether a diagnosis list contains errors
hasErrors :: [Diagnosis] -> Bool
hasErrors = any isErrorDiag

-- | add range to a diagnosis
adjustDiagPos :: Range -> Diagnosis -> Diagnosis
adjustDiagPos r d = d { diagPos = appRange r $ diagPos d }

-- | A uniqueness check yields errors for duplicates in a given list.
checkUniqueness :: (Pretty a, PosItem a, Ord a) => [a] -> [Diagnosis]
checkUniqueness l =
    let vd = filter ( not . null . tail) $ group $ sort l
    in map ( \ vs -> mkDiag Error ("duplicates at '" ++
                                  showSepList (showString " ") shortPosShow
                                  (concatMap getPosList (tail vs)) "'"
                                   ++ " for")  (head vs)) vd
    where shortPosShow :: Pos -> ShowS
          shortPosShow p = showParen True
                           (shows (sourceLine p) .
                            showString "," .
                            shows (sourceColumn p))

-- | The result monad. A failing result should include an error message.
data Result a = Result { diags :: [Diagnosis]
                       , maybeResult :: Maybe a
                       } deriving Show

instance Functor Result where
    fmap f (Result errs m) = Result errs $ fmap f m

instance Monad Result where
  return x = Result [] $ Just x
  r@(Result e m) >>= f = case m of
      Nothing -> Result e Nothing
      Just x -> joinResult r $ f x
  fail s = fatal_error s nullRange

appendDiags :: [Diagnosis] -> Result ()
appendDiags ds = Result ds (Just ())

-- | join two results with a combining function
joinResultWith :: (a -> b -> c) -> Result a -> Result b -> Result c
joinResultWith f (Result d1 m1) (Result d2 m2) = Result (d1 ++ d2) $
    do r1 <- m1
       r2 <- m2
       return $ f r1 r2

-- | join two results
joinResult :: Result a -> Result b -> Result b
joinResult = joinResultWith (\ _ b -> b)

-- | join a list of results that are independently computed
mapR :: (a -> Result a) -> [a] -> Result [a]
mapR ana = foldr (joinResultWith (:)) (Result [] $ Just []) . map ana

-- | a failing result with a proper position
fatal_error :: String -> Range -> Result a
fatal_error s p = Result [Diag Error s p] Nothing

-- | a failing result constructing a message from a type
mkError :: (PosItem a, Pretty a) => String -> a -> Result b
mkError s c = Result [mkDiag Error s c] Nothing

-- | a failing result constructing a message from a type
mkNiceError :: (PosItem a, Pretty a) => GlobalAnnos -> String -> a -> Result b
mkNiceError ga s c = Result [mkNiceDiag ga Error s c] Nothing

-- | add a debug point
debug :: (PosItem a, Pretty a) => Int -> (String, a) -> Result ()
debug n (s, a) = Result [mkDiag Debug
                         (" point " ++ show n ++ "\nVariable "++s++":\n") a ]
                 $ Just ()

-- | add an error message but don't fail
plain_error :: a -> String -> Range -> Result a
plain_error x s p = Result [Diag Error s p] $ Just x

-- | add a warning
warning :: a -> String -> Range -> Result a
warning x s p = Result [Diag Warning s p] $ Just x

-- | add a hint
hint :: a -> String -> Range -> Result a
hint x s p = Result [Diag Hint s p] $ Just x

-- | add a (web interface) message
message :: a -> String -> Result a
message x m = Result [Diag MessageW m nullRange] $ Just x

-- | add a failure message to 'Nothing'
maybeToResult :: Range -> String -> Maybe a -> Result a
maybeToResult p s m = Result (case m of
                              Nothing -> [Diag Error s p]
                              Just _ -> []) m

-- | add a failure message to 'Nothing'
-- (alternative for 'maybeToResult' without 'Range')
maybeToMonad :: Monad m => String -> Maybe a -> m a
maybeToMonad s m = case m of
                        Nothing -> fail s
                        Just v -> return v

-- | check whether no errors are present, coerce into 'Maybe'
resultToMaybe :: Result a -> Maybe a
resultToMaybe (Result ds val) = if hasErrors ds then Nothing else val

-- | adjust positions of diagnoses
adjustPos :: Range -> Result a -> Result a
adjustPos p r =
  r {diags = map (adjustDiagPos p) $ diags r}

-- | Propagate errors using the error function
propagateErrors :: Result a -> a
propagateErrors r =
  case (hasErrors $ diags r, maybeResult r) of
    (False, Just x) -> x
    _ -> error $ unlines $ map show $ diags r

-- ---------------------------------------------------------------------
-- instances for Result
-- ---------------------------------------------------------------------

-- | showing (Parsec) parse errors using our own 'showPos' function
showErr :: ParseError -> String
showErr err = let
    (lookAheads, msgs) = partition ( \ m -> case m of
                     Message str -> isPrefixOf lookaheadPosition str
                     _ -> False) $ errorMessages err
    pos = fromSourcePos (errorPos err)
    poss = pos : foldr (\ s l -> case readPos $
                                 drop (length lookaheadPosition)
                                 $ messageString s of
                        Just p -> p {sourceName = sourceName pos} : l
                        _ -> l) [] lookAheads
    in shows (prettyPoss poss) ":" ++
       showErrorMessages "or" "unknown parse error"
           "expecting" "unexpected" "end of input" msgs

readPos :: String -> Maybe Pos
readPos s = case parse (do
            ls <- getNumber
            char '.'
            cs <- getNumber
            return $ newPos "" (value 10 ls) (value 10 cs)) "" s of
                  Left _ -> Nothing
                  Right x -> Just x

prettyPoss :: [Pos] -> Doc
prettyPoss sp = let
    mi = minimumBy comparePos sp
    ma = maximumBy comparePos sp
    in case comparePos mi ma of
          EQ -> text (showPos ma "")
          _ -> text $ showPos mi "-"
               ++ showPos ma {sourceName = ""} ""

instance Show Diagnosis where
    showsPrec _ = shows . pretty

instance Pretty Diagnosis where
    pretty (Diag k s (Range sp)) =
        (if isMessageW
            then empty
            else text (case k of
                  Error -> "***"
                  _ -> "###") <+> text (show k))
        <> (case sp of
             [] | isMessageW -> empty
                | otherwise  -> comma
             _ -> space <> prettyPoss sp <> comma)
        <+> text s
        where isMessageW = case k of
                           MessageW -> True
                           _        -> False

instance PosItem Diagnosis where
    getRange d = diagPos d

instance Pretty a => Pretty (Result a) where
    pretty (Result ds m) = vcat ((case m of
                                       Nothing -> empty
                                       Just x -> pretty x) :
                                 map pretty ds)
