
{- |

Module      :  $Header$
Copyright   :  (c) Klaus L�ttich and Christian Maeder and Uni Bremen 2002-2003
Licence     :  All rights reserved.

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable


This modul supplies simple and mixfix identifiers. 
A simple identifier is a lexical token given by a string and a start position.

-  A 'place' is a special token within mixfix identifiers.

-  A mixfix identifier may have a compound list. 
   This compound list follows the last non-place token! 
-}

module Common.Id where

import Data.Char
import Common.Lib.Parsec.Pos 

-- identifiers, fixed for all logics

type Pos = SourcePos

-- | unknown position
nullPos :: Pos 
nullPos = newPos "" 0 0 

-- | first 'Pos' or 'nullPos'
headPos :: [Pos] -> Pos 
headPos l = if null l then nullPos else head l

-- | tokens as supplied by the scanner
data Token = Token { tokStr :: String
		   , tokPos :: Pos
		   } deriving (Show)

-- | show the plain string
showTok :: Token -> ShowS
showTok = showString . tokStr

-- | ignore 'tokPos'
instance Eq Token where
   Token s1 _ == Token s2 _ = s1 == s2
 
-- | ignore 'tokPos'
instance Ord Token where
   Token s1 _  <= Token s2 _ = s1 <= s2

-- | shortcut to get positions of surrounding and interspersed tokens
toPos :: Token -> [Token] -> Token -> [Pos]
toPos o l c = map tokPos (o:l++[c])

-- | intersperse seperators
showSepList :: ShowS -> (a -> ShowS) -> [a] -> ShowS
showSepList _ _ [] = id
showSepList _ f [x] = f x
showSepList s f (x:r) = f x . s . showSepList s f r

-- | the special 'place'
place :: String
place = "__"

-- | is a 'place' token
isPlace :: Token -> Bool
isPlace (Token t _) = t == place
 
-- | mixfix and compound identifiers
data Id = Id [Token] [Id] [Pos] 
          -- pos of square brackets and commas of a compound list
	  deriving (Show)

-- for pretty printing see PrettyPrint.hs

-- | ignore positions
instance Eq Id where
    Id tops1 ids1 _ == Id tops2 ids2 _ = (tops1, ids1) == (tops2, ids2)

-- | ignore positions
instance Ord Id where
    Id tops1 ids1 _ <= Id tops2 ids2 _ = (tops1, ids1) <= (tops2, ids2)

-- | shortcut to suppress output for input condition
noShow :: Bool -> ShowS -> ShowS
noShow b s = if b then id else s

-- | shows a compound list 
showIds :: [Id] -> ShowS
showIds is = noShow (null is) $ showString "[" 
	     . showSepList (showString ",") showId is
	     . showString "]"

-- | shows an 'Id', puts final places behind a compound list
showId :: Id -> ShowS
showId (Id ts is _) = 
	let (toks, places) = splitMixToken ts 
	    showToks = showSepList id showTok
	in  showToks toks . showIds is . showToks places

-- | splits off the front and final places 
splitMixToken :: [Token] -> ([Token],[Token])
splitMixToken [] = ([], [])
splitMixToken (h:l) = 
    let (toks, pls) = splitMixToken l
	in if isPlace h && null toks 
	   then (toks, h:pls) 
	   else (h:toks, pls)

-- | ignores final places in an 'Id' (for HasCASL)
stripFinalPlaces :: Id -> Id
stripFinalPlaces (Id ts cs ps) =
    Id (fst $ splitMixToken ts) cs ps 

-- | reconstruct a list with surrounding strings and interspersed commas 
-- with proper position information 
-- that should be preserved by the input function
expandPos :: (Token -> a) -> (String, String) -> [a] -> [Pos] -> [a]
-- expandPos f ("{", "}") [a,b] [(1,1), (1,3), 1,5)] = 
-- [ t"{" , a , t"," , b , t"}" ] where t = f . Token (and proper positions)
expandPos f (o, c) ts ps =
    if null ts then if null ps then map (f . mkSimpleId) [o, c]
       else map f (zipWith Token [o, c] [head ps , last ps])
    else  let n = length ts + 1
              diff = n - length ps
	      ps1 = if diff > 0 then ps ++ replicate diff nullPos
		    -- pad with nullPos
		    else if diff == 0 then ps
			 else take n $ drop (- diff `div` 2) ps
		    -- cut off longer lists on both ends
	      commas j = if n == 2 then [c] else "," : commas (j - 1)
	      seps = map f
		(zipWith Token (o : commas n) ps1)
	  in head seps : concat (zipWith (\ t s -> [t,s]) ts (tail seps))
	    		    
-- | reconstruct the token list of an 'Id'
-- including square brackets and commas of (nested) compound lists.
-- Replace top-level places with the input String 
-- that may be the 'place' itself
getTokenList :: String -> Id -> [Token]
getTokenList placeStr (Id ts cs ps) = 
    let (toks, pls) = splitMixToken ts 
        cts = if null cs then [] else concat 
	      $ expandPos (:[]) ("[", "]") (map (getTokenList place) cs) ps
	      -- although positions will be replaced (by scan)
        convert =  map (\ t -> if isPlace t then t {tokStr = placeStr} else t) 
    in if placeStr == place then toks ++ cts ++ pls -- optimized for place
       else convert toks ++ cts ++ convert pls

-- | compute a meaningful single position from an 'Id' for diagnostics 
posOfId :: Id -> Pos
posOfId (Id ts _ _) = let l = dropWhile isPlace ts 
		      in if null l then -- for invisible "__ __" (only places)
			   headPos $ map tokPos ts
			 else tokPos $ head l

-- | simple ids are just tokens 
type SIMPLE_ID = Token

-- | a 'Token' with 'nullPos'
mkSimpleId :: String -> Token
mkSimpleId s = Token s nullPos

-- | a 'SIMPLE_ID' as 'Id'
simpleIdToId :: SIMPLE_ID -> Id
simpleIdToId sid = Id [sid] [] []

-- | test for a 'SIMPLE_ID'
isSimpleId :: Id -> Bool
isSimpleId (Id ts cs _) = null cs && length ts == 1 

---- some useful predicates for Ids -------------------------------------

-- | has no (toplevel) 'place'
isOrdAppl :: Id -> Bool
isOrdAppl = not . isMixfix

-- | has a place
isMixfix :: Id -> Bool
isMixfix (Id tops _ _) = any isPlace tops 

-- | ends with a place
isPrefix :: Id -> Bool
isPrefix (Id tops _ _) = not (null tops) && not (isPlace (head tops)) 
			 && isPlace (last tops)

-- | starts with a place
isPostfix :: Id -> Bool
isPostfix (Id tops _ _) = not (null tops) &&  isPlace (head  tops) 
			  && not (isPlace (last tops)) 

-- | is classical infix id with three tokens, the middle one is a non-place 
isInfix2 :: Id -> Bool
isInfix2 (Id ts _ _) = 
    case ts of 
	    [e1, e2, e3] -> isPlace e1 && not (isPlace e2) 
			    && isPlace e3 
	    _ -> False

-- | starts and ends with a place
isInfix :: Id -> Bool
isInfix (Id tops _ _) = not (null tops) &&  isPlace (head tops) 
			&& isPlace (last tops)

-- | has a place but neither starts nor ends with one
isSurround :: Id -> Bool
isSurround i@(Id tops _ _) = not (null tops) && (isMixfix i)
			     && not (isPlace (head tops)) 
				    && not (isPlace (last tops)) 

-- | has a compound list
isCompound :: Id -> Bool
isCompound (Id _ cs _) = not $ null cs

---- helper class -------------------------------------------------------

{- | This class is derivable with DrIFT.
   Its main purpose is to have a function that operates on
   constructors with a 'Pos' or list of 'Pos' field. During parsing, mixfix
   analysis and ATermConversion this function might be very useful.
-}

class PosItem a where
    up_pos    :: (Pos -> Pos)    -> a -> a
    up_pos_l  :: ([Pos] -> [Pos]) -> a -> a
    get_pos   :: a -> Maybe Pos
    get_pos_l :: a -> Maybe [Pos]
    up_pos_err  :: String -> a
    up_pos_err fn = 
	error ("function \"" ++ fn ++ "\" is not implemented")
    up_pos _    = id
    up_pos_l _  = id
    get_pos   _ = Nothing
    get_pos_l _ = Nothing
    
-------------------------------------------------------------------------

-- | handcoded instance
instance PosItem Token where
    up_pos fn1 (Token aa ab) = (Token aa (fn1 ab))
    get_pos (Token _ ab) = Just ab

-- | handcoded instance
instance PosItem Id where
    up_pos_l fn1 (Id aa ab ac) = (Id aa ab (fn1 ac))
    get_pos_l (Id _ _ ac) = Just ac
    get_pos = Just . posOfId
