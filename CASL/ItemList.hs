
{- HetCATS/CASL/ItemList.hs
   $Id$
   Authors: Christian Maeder
   Year:    2002
   
   generically parse "<keyword>/<keywords> ITEM ; ... ; ITEM"
-}

module ItemList where

import Id
import Keywords
import Lexer
import AS_Annotation
import Anno_Parser(annotationL)
import Maybe
import Parsec
import Token
import List(delete)

-- ----------------------------------------------
-- annotations
-- ----------------------------------------------

-- skip to leading annotation and read many
annos :: GenParser Char st [Annotation]
annos = skip >> many (annotationL << skip)

-- annotations on one line
lineAnnos :: GenParser Char st [Annotation]
lineAnnos = do p <- getPosition
	       do a <- annotationL
		  skip
		  q <- getPosition
		  if sourceLine q <= sourceLine p + 1 then
		      do l <- lineAnnos
			 return (a:l)
		      else return [a]
		 <|> return []

-- optional semicolon followed by annotations on the same line
optSemi :: GenParser Char st (Maybe Token, [Annotation])
optSemi = do (a1, s) <- try (bind (,) annos semiT)
             a2 <- lineAnnos 			     
	     return (Just s, a1 ++ a2)
          <|> do a <- lineAnnos
		 return (Nothing, a)

-- succeeds if an item is not continued after a semicolon
tryItemEnd :: [String] -> GenParser Char st ()
tryItemEnd l = 
    try (do c <- lookAhead (annos >> 
			      (single (oneOf "\"([{")
			       <|> placeS
			       <|> scanAnySigns
			       <|> many scanLPD))
	    if null c || c `elem` l then return () else unexpected c)


-- remove quantifier exists from casl_reserved_word 
-- because it may start a formula in "axiom/axioms ... \;"
startKeyword :: [String]
startKeyword = dotS:cDot:
		   (delete existsS casl_reserved_words)

appendAnno :: Annoted a -> [Annotation] -> Annoted a
appendAnno (Annoted x p l r) y = Annoted x p l (r++y)

addLeftAnno :: [Annotation] -> a -> Annoted a
addLeftAnno l i = Annoted i [] l []

annoParser :: GenParser Char st a -> GenParser Char st (Annoted a)
annoParser parser = bind addLeftAnno annos parser

annosParser :: GenParser Char st a -> GenParser Char st [Annoted a]
annosParser parser = do (as, is) <- annos `separatedBy` parser
			if null is then unexpected ("empty item list")
			   else let bs = zipWith addLeftAnno (init as) is
				in return (init bs ++ 
					   [appendAnno (last bs) (last as)])

itemList :: String -> GenParser Char st b
               -> ([Annoted b] -> [Pos] -> a) -> GenParser Char st a
itemList = auxItemList startKeyword

auxItemList :: [String] -> String -> GenParser Char st b
               -> ([Annoted b] -> [Pos] -> a) -> GenParser Char st a

auxItemList startKeywords keyword parser constr =
    do p <- pluralKeyword keyword
       (vs, ts, ans) <- itemAux startKeywords (annoParser parser)
       let r = zipWith appendAnno vs ans in 
	   return (constr r (map tokPos (p:ts)))

itemAux :: [String] -> GenParser Char st a 
	-> GenParser Char st ([a], [Token], [[Annotation]])
itemAux startKeywords itemParser = 
    do a <- itemParser
       (m, an) <- optSemi
       case m of Nothing -> return ([a], [], [an])
                 Just t -> do tryItemEnd startKeywords
			      return ([a], [t], [an])
	                   <|> 
	                   do (as, ts, ans) <- itemAux startKeywords itemParser
			      return (a:as, t:ts, an:ans)

