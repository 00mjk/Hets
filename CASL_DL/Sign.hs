{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

Signatures for DL logics, as extension of CASL signatures.
-}

module CASL_DL.Sign where

import qualified Data.Map as Map
import Common.Id
import Common.Doc
import Common.DocUtils

import CASL.AS_Basic_CASL
import CASL_DL.AS_CASL_DL
import CASL_DL.Print_AS ()

import Data.List (union, (\\), isPrefixOf)
import Control.Exception
import OWL_DL.AS (QName)
import OWL_DL.ReadWrite ()

data CASL_DLSign =
    CASL_DLSign { annoProperties  :: Map.Map SIMPLE_ID PropertyType
                , annoPropertySens :: [AnnoAppl]
                } deriving (Show, Eq)

data PropertyType = AnnoProperty
                  | OntoProperty deriving (Show,Eq)

data AnnoAppl = AnnoAppl SIMPLE_ID Id AnnoLiteral
              deriving (Show,Eq)

data AnnoLiteral = AL_Term (TERM DL_FORMULA)
                 | AL_URI  QName
                 | AL_Id   Id
              deriving (Show,Eq)

emptyCASL_DLSign :: CASL_DLSign
emptyCASL_DLSign = CASL_DLSign Map.empty []

addCASL_DLSign :: CASL_DLSign -> CASL_DLSign -> CASL_DLSign
addCASL_DLSign a b = a
     { annoProperties =
           Map.unionWithKey (throwAnnoError "CASL_DL.Sign.addCASL_DLSign:")
                  (annoProperties a) (annoProperties b)
     , annoPropertySens = union (annoPropertySens a) (annoPropertySens b)
     }

throwAnnoError :: String -> SIMPLE_ID
               -> PropertyType -> PropertyType -> PropertyType
throwAnnoError s k e1 e2 =
    if e1 == e2
       then e1
       else error (s++" Annotation Properties and Ontology Properties \
                          \must have distinct names! ("++show k++")")

diffCASL_DLSign :: CASL_DLSign -> CASL_DLSign -> CASL_DLSign
diffCASL_DLSign a b = a
     { annoProperties = Map.difference (annoProperties a) (annoProperties b)
     , annoPropertySens = (annoPropertySens a) \\ (annoPropertySens b)
     }

isSubCASL_DLSign :: CASL_DLSign -> CASL_DLSign -> Bool
isSubCASL_DLSign a b =
    Map.isSubmapOf (annoProperties a) (annoProperties b) &&
    (annoPropertySens a `isSublistOf` annoPropertySens b)

instance Pretty CASL_DLSign where
    pretty dlSign = if Map.null $ annoProperties dlSign
                    then assert (null $ annoPropertySens dlSign) empty
                    else printPropertyList AnnoProperty 
                                           "%OWL_DLAnnoProperties(" 
                         $+$ 
                         printPropertyList OntoProperty 
                                           "%OWL_DLOntologyProperties("
                         $+$  
                         if null (annoPropertySens dlSign) 
                         then empty
                         else text "%OWL_DLAnnotations(" <+> 
                              vcat (punctuate (text "; ") $ 
                                    (map pretty $ 
                                     annoPropertySens dlSign)) <+> 
                              text ")%"
        where propertyList ty = filter (\ (_,x) -> x==ty) $
                                 Map.toList $ annoProperties dlSign
              printPropertyList ty str =
                  case propertyList ty of
                    [] -> empty
                    l  -> text str <+> 
                          fcat (punctuate comma $ 
                                map (pretty . fst) l) <+> 
                          text ")%"


instance Pretty AnnoAppl where
    pretty (AnnoAppl rel subj obj) = pretty rel <> 
                                     parens (pretty subj<>comma<>pretty obj)

instance Pretty AnnoLiteral where
    pretty annoLit = case annoLit of
                       AL_Term t -> pretty t
                       AL_URI u  -> quotes $ text $ show u
                       AL_Id i   -> pretty i

isSublistOf :: (Eq a) => [a] -> [a] -> Bool
isSublistOf [] _ = True
isSublistOf _ [] = False
isSublistOf ys l@(_:l')
    | length ys <= length l = (ys `isPrefixOf` l) || (ys `isSublistOf` l')
    | otherwise = False
