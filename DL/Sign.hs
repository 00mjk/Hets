{- |
Module      :  $Header$
Description :  Signaure for DL
Copyright   :  (c) Dominik Luecke, Uni Bremen 2008
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  experimental
Portability :  non-portable (imports Logic.Logic)

The signatures for DL as they are extracted from the spec.
-}

module DL.Sign where

import Common.Id
import Common.AS_Annotation()
import Common.Doc
import Common.DocUtils
import qualified Data.Set as Set
import Common.Result as Result

data DLSymbol = DLSymbol
	{
		symName :: Id
	,   symType :: SymbType
	}
	deriving (Eq, Ord, Show)

data DataPropType = DataPropType Id Id
		deriving (Eq, Ord, Show)
		
data ObjPropType = ObjPropType Id Id
		deriving (Eq, Ord, Show)
			
data IndivType = IndivType [Id]
		deriving (Eq, Ord, Show)

data SymbType = ClassSym | 
				DataProp DataPropType |
				ObjProp ObjPropType |
				Indiv IndivType
				
	deriving (Eq, Ord, Show)
	
type RawDLSymbol = Id

topSort :: Id
topSort = stringToId "Thing"
	
instance Pretty DLSymbol where
	pretty = text . show

data Sign = Sign 
	{
		classes :: Set.Set Id 
	,   funDataProps :: Set.Set QualDataProp
	,   dataProps :: Set.Set QualDataProp
	,   funcObjectProps :: Set.Set QualObjProp
	,   objectProps :: Set.Set QualObjProp
	,   individuals :: Set.Set QualIndiv
	}
	deriving (Eq)

showSig ::  Sign -> String
showSig sg = "%[\n" ++
			 "Class: " ++ (concatComma $ map show $ Set.toAscList $ classes sg) ++ "\n" ++
			 "Functional Data Properties: " ++ (concatComma $ map show $ Set.toAscList $ funDataProps sg) ++ "\n" ++
			 "Data Properties: " ++ (concatComma $ map show $ Set.toAscList $ dataProps sg) ++ "\n" ++		
		     "Functional Onject Properties: " ++ (concatComma $ map show $ Set.toAscList $ funcObjectProps sg) ++ "\n" ++
			 "Object Properties: " ++ (concatComma $ map show $ Set.toAscList $ objectProps sg) ++ "\n" ++		
			 "Individuals: " ++ (concatComma $ map show $ Set.toAscList $ individuals sg) ++ "\n"
			 ++ "\n]%"

instance Show Sign where
	show =  showSig 
			 
instance Pretty Sign where
	pretty sg = text $ show sg
	
data QualIndiv = QualIndiv
	{
		iid   :: Id
	,   types :: [Id]
	}
	deriving (Eq,Ord)

showIndiv :: QualIndiv -> String
showIndiv myId = (show $ iid myId) ++ " :: " ++ (concatComma $ map show $ types myId)

instance Show QualIndiv where
	show = showIndiv

data QualDataProp = QualDataProp
	{
		nameD   :: Id
	,	domD    :: Id
	,	rngD    :: Id
	}
	deriving (Eq,Ord)
	
data QualObjProp = QualObjProp
	{
		nameO   :: Id
	,	domO    :: Id
	,	rngO    :: Id
	}
	deriving (Eq, Ord)

showDataProp :: QualDataProp -> String
showDataProp pp = (show $  nameD pp) ++ " :: " ++ (show $ domD pp) ++ " -> " ++ (show $ rngD pp)

showObjProp :: QualObjProp -> String
showObjProp pp = (show $  nameO pp) ++ " :: " ++ (show $ domO pp) ++ " -> " ++ (show $ rngO pp)

instance Show QualDataProp where
	show = showDataProp
	
instance Show QualObjProp where
	show = showObjProp
	
emptyDLSig :: Sign
emptyDLSig = Sign{
				  classes = Set.empty
				, funDataProps = Set.empty
				, dataProps = Set.empty
				, funcObjectProps = Set.empty
				, objectProps = Set.empty
                , individuals = Set.empty
				}

				
data DLMorphism = DLMorphism
  { msource :: Sign
  , mtarget :: Sign
  } deriving (Eq, Show)

emptyMor :: DLMorphism  				
emptyMor = DLMorphism
 	{
 	 msource = emptyDLSig
 	,mtarget = emptyDLSig
 	}
  				
instance Pretty DLMorphism where
 	pretty = text . show

compDLmor :: DLMorphism -> DLMorphism -> Result.Result DLMorphism
compDLmor mor1 mor2 = 
	case (mtarget mor1 == msource mor2) of
		True -> Result.hint
			emptyMor
					{
						msource = msource mor1
					,   mtarget = mtarget mor2
					} 	
			"All fine"
			nullRange
		False -> Result.fatal_error "Not composable" nullRange

idMor :: Sign -> DLMorphism
idMor sig = emptyMor
	{
		msource = sig
	,   mtarget = sig
	}
	
concatComma :: [String] -> String
concatComma [] = ""
concatComma (x:[]) = x
concatComma (x:xs) = x ++ ", " ++ concatComma xs
