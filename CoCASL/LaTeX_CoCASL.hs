{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski and Uni Bremen 2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  till@tzi.de
Stability   :  experimental
Portability :  portable 
   
   latex output of the abstract syntax
-}

module CoCASL.LaTeX_CoCASL where

import CoCASL.AS_CoCASL
import CoCASL.CoCASLSign
import CoCASL.Print_AS
import Common.Keywords 
import Common.PrettyPrint -- todo provide real latex printers 
import Common.Lib.Pretty
import Common.PrintLaTeX
import Common.LaTeX_utils
import Common.PPUtils
import Common.AS_Annotation
import CASL.AS_Basic_CASL
import CASL.LaTeX_AS_Basic
import Data.Char(toUpper)

instance PrintLaTeX C_FORMULA where 
    printLatex0 = printText0

instance PrintLaTeX C_SIG_ITEM where 
    printLatex0 ga (CoDatatype_items l _) = 
	hc_sty_sig_item_keyword ga (cotypeS++pluralS l) <\+> 
	set_tabbed_nest_latex (semiAnno_latex ga l) 

instance PrintLaTeX CODATATYPE_DECL where
    printLatex0 ga (CoDatatype_decl s a _) = 
	printLatex0 ga s <\+> case a of 
        [] -> error "PrettyPrint CoCASL.CODATATYPE_DECL"
        h : t -> sep_latex 
	   (hc_sty_axiom defnS <> setTab_latex<~>
	      (printLatex0 ga h)<>casl_normal_latex "~":
	    (map (\x -> tabbed_nest_latex (latex_macro 
                                                 "\\hspace*{-0.84mm}"<> ---}
					   casl_normal_latex "\\textbar") 
			    <~> (printLatex0 ga x)<>casl_normal_latex "~") t)) 

instance PrintLaTeX COALTERNATIVE where
    printLatex0 ga (CoTotal_construct n l _) = tabbed_nest_latex (
	printLatex0 ga n <> if null l then empty 
		            else parens_tab_latex ( semiT_latex ga l))
    printLatex0 ga (CoPartial_construct n l _) = 
	tabbed_nest_latex (printLatex0 ga n 
				 <> parens_tab_latex 
					( semiT_latex ga l)
				 <> hc_sty_axiom quMark )
    printLatex0 ga (CoSubsorts l _) = 
	sp_text (axiom_width s') s'' <\+> commaT_latex ga l 
	where s'  = sortS ++ pluralS l
	      s'' = '\\':map toUpper s' ++ "[ID]"

instance PrintLaTeX COCOMPONENTS where
    printLatex0 ga (CoSelect l s _) = 
	commaT_latex ga l <> colon_latex <> printLatex0 ga s 

instance PrintLaTeX C_BASIC_ITEM where 
    printLatex0 ga (CoFree_datatype l _) = 
	fsep_latex [hc_sty_plain_keyword cofreeS
		    <~> setTab_latex
		    <> hc_sty_plain_keyword (typeS ++ pluralS l)
		   ,tabbed_nest_latex $ semiAnno_latex ga l]
    printLatex0 ga (CoSort_gen l _) = 
	hang_latex (hc_sty_plain_keyword cogeneratedS 
		    <~> setTab_latex<> condCoTypeS) 9 $ 
	           tabbed_nest_latex $ condBraces  
				  (vcat (map (printLatex0 ga) l))
	where condCoTypeS = 
		  if isOnlyDatatype then 
		     hc_sty_plain_keyword (cotypeS++pluralS l) 
		  else empty
	      condBraces d = 
		  if isOnlyDatatype then 
		     case l of
		     [x] -> case x of
			    Annoted (Ext_SIG_ITEMS 
                                     (CoDatatype_items l' _)) _ lans _ -> 
				vcat (map (printLatex0 ga) lans) 
					 $$ semiAnno_latex ga l'
			    _ -> error "wrong implementation of isOnlyDatatype"
                     _ -> error "wrong implementation of isOnlyDatatype"
		  else braces_latex d
	      isOnlyDatatype = 
		  case l of
		  [x] -> case x of 
			 Annoted (Ext_SIG_ITEMS 
                                  (CoDatatype_items _ _)) _ _ _ -> True
			 _ -> False
		  _  -> False

instance PrintLaTeX CoCASLSign where 
    printLatex0 = printText0
