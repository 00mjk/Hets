{-
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, Wiebke Herding, C. Maeder, Uni Bremen 2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

  Parser for modal logic extension of CASL
-}

module Modal.Parse_AS where

import Common.AnnoState
import Common.AS_Annotation
import Common.Id
import Common.Keywords
import Common.Lexer
import Common.Token
import Modal.AS_Modal
import Text.ParserCombinators.Parsec
import CASL.Formula
import CASL.OpItem

modalFormula :: AParser st M_FORMULA
modalFormula = 
    do o <- oBracketT
       m <- modality []
       c <- cBracketT
       f <- formula modal_reserved_words
       return (BoxOrDiamond True m f $ toPos o [] c)
    <|> 
    do o <- asKey lessS
       m <- modality [greaterS] -- do not consume matching ">"!
       c <- asKey greaterS
       f <- formula modal_reserved_words
       return (BoxOrDiamond False m f $ toPos o [] c)
    <|> 
    do d <- asKey diamondS
       f <- formula modal_reserved_words
       let p = tokPos d
       return (BoxOrDiamond False (Simple_mod $ Token emptyS p) f [p])

modality :: [String] -> AParser st MODALITY
modality ks = 
    do t <- term (ks ++ modal_reserved_words)
       return $ Term_mod t
   <|> return (Simple_mod $ mkSimpleId emptyS)

instance AParsable M_FORMULA where
  aparser = modalFormula

rigor :: AParser st RIGOR
rigor = (asKey rigidS >> return Rigid) 
	<|> (asKey flexibleS >> return Flexible)

rigidSigItems :: AParser st M_SIG_ITEM
rigidSigItems = 
    do r <- rigor
       do itemList modal_reserved_words opS opItem (Rigid_op_items r)
	 <|> itemList modal_reserved_words predS predItem (Rigid_pred_items r)

instance AParsable M_SIG_ITEM where
  aparser = rigidSigItems

mKey :: AParser st Token
mKey = asKey modalityS <|> asKey modalitiesS

mBasic :: AParser st M_BASIC_ITEM
mBasic = 
    do (as, fs, ps) <- mItem simpleId
       return (Simple_mod_decl as fs ps)
    <|>
    do t <- asKey termS
       (as, fs, ps) <- mItem (sortId modal_reserved_words)
       return (Term_mod_decl as fs (tokPos t : ps))

mItem :: AParser st a -> AParser st ([Annoted a], [AnModFORM], [Pos])
mItem pr = do 
       c <- mKey
       (as, ps) <- auxItemList (modal_reserved_words ++ startKeyword)
		   [c] pr (,)
       do o <- oBraceT
	  (fs, qs) <- annoParser (formula modal_reserved_words)
		      `separatedBy` anSemi
	  p <- cBraceT
          return (as, fs, ps ++ toPos o qs p)
	<|>  return (as, [], ps)
		
instance AParsable M_BASIC_ITEM where
  aparser = mBasic
