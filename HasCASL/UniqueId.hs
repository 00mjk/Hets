{- |
Module      :  $Header$
Copyright   :  (c) Uni Bremen 2003
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  experimental
Portability :  portable 

   Creating and searching unique identifier.
-}


module HasCASL.UniqueId (
       -- * Creating unique identifiers
         distinctOpIds
       , newName
       -- * Searching for an identifier
       , findUniqueId
       )where

import HasCASL.As
import HasCASL.Le
import HasCASL.Unify
import Common.Id
import qualified Common.Lib.Map as Map hiding (map)

-- | Generates distinct names for overloaded function identifiers.
distinctOpIds :: Int -> [(Id, OpInfos)] -> [(Id, OpInfo)]
distinctOpIds _ [] = []
distinctOpIds n ((i,OpInfos info) : idInfoList) = 
    case info of
    [] -> distinctOpIds 2 idInfoList
    [hd] -> (i, hd) : distinctOpIds 2 idInfoList
    hd : tl -> (newName i n, hd) : 
	     distinctOpIds (n + 1) ((i, OpInfos tl) : idInfoList)

-- | Adds a number to the name of an identifier.
newName :: Id -> Int -> Id
newName (Id tlist idlist poslist) n = 
  Id (tlist ++ [mkSimpleId $ '0' : show n]) idlist poslist

-- | Searches for the real name of an overloaded identifier.
findUniqueId :: Env -> UninstOpId -> TypeScheme -> Maybe (Id, OpInfo)
findUniqueId env uid ts = 
    let OpInfos l = Map.findWithDefault (OpInfos []) uid (assumps env)
	fit :: Int -> [OpInfo] -> Maybe (Id, OpInfo)
	fit n tl = 
	    case tl of
		   [] -> Nothing
		   oi:rt -> if isUnifiable (typeMap env) 0 ts $ opType oi then 
			    Just (if null rt then uid else newName uid n, oi)
			    else fit (n + 1) rt
    in fit 2 l
       

