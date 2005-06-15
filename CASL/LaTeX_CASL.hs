{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  experimental
Portability :  portable

latex printing of sign and morphism data types

-}

module CASL.LaTeX_CASL where

import Common.Keywords
import CASL.LaTeX_AS_Basic
import CASL.Sign
import CASL.Morphism
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import Common.Lib.Pretty
import Common.PPUtils
import Common.LaTeX_utils
import Common.PrintLaTeX

instance PrintLaTeX OpType where
  printLatex0 ga ot = printLatex0 ga $ toOP_TYPE ot

instance PrintLaTeX PredType where
  printLatex0 ga pt = printLatex0 ga $ toPRED_TYPE pt

instance (PrintLaTeX f, PrintLaTeX e) => PrintLaTeX (Sign f e) where
    printLatex0 ga s = 
	casl_keyword_latex sortS <\+> commaT_latex ga (Set.toList $ sortSet s) 
	$$ 
        (if Rel.null (sortRel s) then empty
            else casl_keyword_latex sortS <\+> 
             (vcat $ map printRel $ Map.toList $ Rel.toMap $ sortRel s))
	$$ 
	vcat (map (\ (i, t) -> 
		   casl_keyword_latex opS <\+>
		   printLatex0 ga i <\+> colon_latex <>
		   printLatex0 ga t) 
	      $ concatMap (\ (o, ts) ->
			  map ( \ ty -> (o, ty) ) $ Set.toList ts)
	       $ Map.toList $ opMap s)
	$$ 
	vcat (map (\ (i, t) -> 
		   casl_keyword_latex predS <\+>
		   printLatex0 ga i <\+> colon_latex <\+>
		   printLatex0 ga (toPRED_TYPE t)) 
	     $ concatMap (\ (o, ts) ->
			  map ( \ ty -> (o, ty) ) $ Set.toList ts)
	     $ Map.toList $ predMap s)
     where printRel (subs, supersorts) =
             printLatex0 ga subs <\+> hc_sty_axiom lessS 
                             <\+> printSet ga supersorts

instance PrintLaTeX Symbol where
  printLatex0 ga sy = 
    printLatex0 ga (symName sy) <> 
    (if isEmpty t then empty
      else colon_latex <> t)
    where
    t = printLatex0 ga (symbType sy)

instance PrintLaTeX SymbType where
  printLatex0 ga (OpAsItemType ot) = printLatex0 ga ot
  printLatex0 ga (PredAsItemType pt) = printLatex0 ga pt
  printLatex0 _ SortAsItemType = empty 

instance PrintLaTeX Kind where
  printLatex0 _ SortKind = casl_keyword_latex sortS
  printLatex0 _ FunKind = casl_keyword_latex opS
  printLatex0 _ PredKind = casl_keyword_latex predS

instance PrintLaTeX RawSymbol where
  printLatex0 ga rsym = case rsym of
    ASymbol sy -> printLatex0 ga sy
    AnID i -> printLatex0 ga i
    AKindedId k i -> printLatex0 ga k <\+> printLatex0 ga i

instance (PrintLaTeX f, PrintLaTeX e, PrintLaTeX m) => 
    PrintLaTeX (Morphism f e m) where
  printLatex0 ga mor = 
   let printPair (s1,s2) = printLatex0 ga s1 <\+> hc_sty_axiom "\\mapsto" 
                               <\+> printLatex0 ga s2 
   in braces_latex (vcat (map printPair $ Map.toList $ Map.filterWithKey (/=) 
                         $ morphismToSymbMap mor))
   $$ printLatex0 ga (extended_map mor)
   <\+> colon_latex $$ 
   braces_latex (printLatex0 ga $ msource mor) <\+> 
   hc_sty_axiom "\\rightarrow" <\+> 
   braces_latex (printLatex0 ga $ mtarget mor)
