
{- HetCATS/GlobalAnnotations.hs
   $Id$
   Author: Klaus L�ttich
   Year:   2002
-}

{- |
   Maintainer  :  hets@tzi.de
   Stability   :  provisional
   Portability :  portable
    
   Data structures for global annotations
-}

module Common.GlobalAnnotations where

import Common.Id

import qualified Common.Lib.Map as Map
import qualified Common.Lib.Rel as Rel
import qualified Common.Lib.Set as Set
import Common.AS_Annotation

data GlobalAnnos = GA { prec_annos     :: PrecedenceGraph
		      , assoc_annos    :: AssocMap
		      , display_annos  :: DisplayMap
		      , literal_annos  :: LiteralAnnos
		      , literal_map    :: LiteralMap
		      } deriving (Show)

emptyGlobalAnnos :: GlobalAnnos
emptyGlobalAnnos = GA { prec_annos    = Rel.empty
		      , assoc_annos   = Map.empty
		      , display_annos = Map.empty
		      , literal_annos = emptyLiteralAnnos
		      , literal_map   = Map.empty
		      } 

emptyLiteralAnnos :: LiteralAnnos
emptyLiteralAnnos = LA { string_lit  = Nothing
			, list_lit = Set.empty
			, number_lit = Nothing
			, float_lit  = Nothing
			}

type PrecedenceGraph = Rel.Rel Id

type AssocMap = Map.Map Id AssocEither

type DisplayMap = Map.Map Id (Map.Map Display_format String)

type LiteralMap = Map.Map Id LiteralType

data LiteralType = StringCons Id  -- id of null string 
		 | StringNull
		 | ListCons Id Id  -- brackets and null list
                 | ListNull Id -- brackets
		 | NoLiteral -- as error value
		 | Number
		 | Fraction 
		 | Floating
		   deriving (Show,Eq)

data LiteralAnnos = LA { string_lit :: Maybe (Id,Id)
                       , list_lit :: Set.Set (Id, Id, Id)
		       , number_lit :: Maybe Id
		       , float_lit  :: Maybe (Id,Id)
		       } deriving (Show)

