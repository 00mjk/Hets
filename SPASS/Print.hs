{- |
Module      :  $Header$
Description :  Pretty printing for SPASS signatures.
Copyright   :  (c) Rene Wagner, Uni Bremen 2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luettich@tzi.de
Stability   :  provisional
Portability :  unknown

Pretty printing for SPASS signatures.
   Refer to <http://spass.mpi-sb.mpg.de/webspass/help/syntax/dfgsyntax.html>
   for the SPASS syntax documentation.

-}

module SPASS.Print where

import Maybe

import Common.AS_Annotation
import Common.Doc
import Common.DocUtils

import SPASS.Sign
import SPASS.Conversions

instance Pretty Sign where
  pretty = pretty . signToSPLogicalPart

{- |
  Helper function. Generates a '.' as a Doc.
-}

endOfListS :: String
endOfListS = "end_of_list."

{- |
  Creates a Doc from a SPASS Problem.
-}
instance Pretty SPProblem where
  pretty p = text "begin_problem" <> parens (text (identifier p)) <> dot
    $+$ pretty (description p)
    $+$ pretty (logicalPart p)
    $+$ printSettings (settings p)
    $+$ text "end_problem."

{- |
  Creates a Doc from a SPASS Logical Part.
-}
instance Pretty SPLogicalPart where
  pretty lp =
    pretty (symbolList lp)
    $+$ (case declarationList lp of
           [] -> empty
           l -> text "list_of_declarations." 
                $+$ vcat (map pretty l)
                $+$ text endOfListS)
    $+$ vcat (map pretty $ formulaLists lp)

{- |
  Creates a Doc from a SPASS Symbol List.
-}
instance Pretty SPSymbolList where
  pretty sl = text "list_of_symbols."
    $+$ printSignSymList "functions" (functions sl)
    $+$ printSignSymList "predicates" (predicates sl)
    $+$ printSignSymList "sorts" (sorts sl)
    $+$ printSignSymList "operators" (operators sl)
    $+$ printSignSymList "quantifiers" (quantifiers sl)
    $+$ text endOfListS
    where 
      printSignSymList lname list = case list of
        [] -> empty
        _ -> text lname <> 
               brackets (vcat $ punctuate comma $ map pretty list) <> dot

{-|
  Helper function. Creates a Doc from a Signature Symbol.
-}
instance Pretty SPSignSym where
  pretty ssym = case ssym of 
      SPSimpleSignSym s -> text s
      _ -> parens (text (sym ssym) <> comma <> pretty (arity ssym))

{- |
  Creates a Doc from a SPASS Declaration
-}
instance Pretty SPDeclaration where
  pretty d = case d of
    SPSubsortDecl {sortSymA= a, sortSymB= b} ->
      text "subsort" <> parens (text a <> comma <> text b) <> dot
    SPTermDecl {termDeclTermList= l, termDeclTerm= t} ->
      pretty (SPQuantTerm {quantSym= SPForall, variableList= l, qFormula= t})
                 <> dot
    SPSimpleTermDecl t ->
      pretty t <> dot
    SPPredDecl {predSym= p, sortSyms= slist} ->
      pretty (SPComplexTerm {symbol= (SPCustomSymbol "predicate"), arguments= 
          (map (\x-> SPSimpleTerm (SPCustomSymbol x)) (p:slist))}) <> dot
    SPGenDecl {sortSym= s, freelyGenerated= freelygen, funcList= l} ->
      text "sort" <+> text s <+> (if freelygen then text "freely" else empty)
               <+> text "generated by" 
               <+> brackets (hcat $ punctuate comma $ map text l) <> dot

{- |
  Creates a Doc from a SPASS Formula List
-}
instance Pretty SPFormulaList where
  pretty l = text "list_of_formulae" <> parens (pretty (originType l)) <> dot
    $+$ vcat (map (\ x -> printFormula x <> dot) $ formulae l)
    $+$ text endOfListS

{- |
  Creates a Doc from a SPASS Origin Type
-}
instance Pretty SPOriginType where
  pretty t = text $ case t of
    SPOriginAxioms      -> "axioms"
    SPOriginConjectures -> "conjectures"

{- |
  Creates a Doc from a SPASS Formula. Needed since SPFormula is just a
  'type SPFormula = Named SPTerm' and thus instanciating Pretty is not
  possible.
-}
printFormula :: SPFormula-> Doc
printFormula f =
  text "formula" <> parens (pretty (sentence f) <> comma <> text (senName f))

{- |
  Creates a Doc from a SPASS Term.
-}
instance Pretty SPTerm where
  pretty t = case t of
    SPQuantTerm{quantSym= qsym, variableList= tlist, qFormula= tt} ->
        pretty qsym <> 
        parens (brackets (printTermList tlist) <> comma <> pretty tt)
    SPSimpleTerm stsym -> pretty stsym
    SPComplexTerm{symbol= ctsym, arguments= args} -> 
        pretty ctsym <> 
               if null args then empty else parens (printTermList args)
    where
      printTermList = hcat . punctuate comma . map pretty

{- |
  Creates a Doc from a SPASS Quantifier Symbol.
-}
instance Pretty SPQuantSym where
  pretty qs = text $ case qs of
    SPForall             -> "forall"
    SPExists             -> "exists"
    SPCustomQuantSym cst -> cst

{- |
  Creates a Doc from a SPASS Symbol.
-}
-- printSymbol :: SPSymbol-> Doc
instance Pretty SPSymbol where
    pretty s = text $ case s of
     SPEqual            -> "equal"
     SPTrue             -> "true"
     SPFalse            -> "false"
     SPOr               -> "or"
     SPAnd              -> "and"
     SPNot              -> "not"
     SPImplies          -> "implies"
     SPImplied          -> "implied"
     SPEquiv            -> "equiv"
     SPCustomSymbol cst -> cst

{- |
  Creates a Doc from a SPASS description.
-}
instance Pretty SPDescription where
  pretty d = 
    let sptext str v = text str <> parens (textBraces $ text v) <> dot
        mtext str = maybe empty $ sptext str
    in text "list_of_descriptions."
    $+$ sptext "name" (name d)
    $+$ sptext "author" (author d)
    $+$ mtext "version" (version d)
    $+$ mtext "logic" (logic d)
    $+$ text "status" <> parens (pretty $ status d) <> dot
    $+$ sptext "description" (desc d)
    $+$ mtext "date" (date d)
    $+$ text endOfListS

{- |
  surrounds  a doc with "{*  *}" as required for some of the
  description fields and the settings.
-}
textBraces :: Doc -> Doc
textBraces d = text "{* " <> d <> text " *}"

{- |
  Creates a Doc from an 'SPLogState'.
-}
instance Pretty SPLogState where
  pretty s = text $ case s of
    SPStateSatisfiable   -> "satisfiable"
    SPStateUnsatisfiable -> "unsatisfiable"
    SPStateUnknown       -> "unknown"

printSettings :: [SPSetting] -> Doc
printSettings [] = empty
printSettings l = case l of
  [] -> empty
  _ -> 
    text "list_of_settings(SPASS)." $+$
    textBraces (vcat (map (pretty) l)) $+$
    text endOfListS

instance Pretty SPSetting where
    pretty (SPFlag sw v) = 
        text "set_flag" <> parens (text sw <> comma <> text v) <>dot
