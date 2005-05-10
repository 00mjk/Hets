{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

-}

module Common.ATerm.Unshared
    (ATerm(..),
     fromATerm,
     getATermFull,
     toATermTable)
    where

import Common.ATerm.AbstractSyntax
import Common.ATerm.Conversion

data ATerm = AAppl String [ATerm] [ATerm]
           | AList [ATerm]        [ATerm]
           | AInt  Integer        [ATerm]
             deriving (Eq,Ord)

fromATerm :: ShATermConvertible t => ATerm -> t
fromATerm = fromShATerm . toATermTable 

getATermFull :: ATermTable -> ATerm
getATermFull at = 
    let t = getATerm at
    in case t of
       (ShAInt i as)    -> AInt i (map conv as)
       (ShAList l as)   -> AList (map conv l) (map conv as)
       (ShAAppl c l as) -> AAppl c (map conv l) (map conv as)
    where conv t = getATermFull (getATermByIndex1 t at) 

toATermTable :: ATerm -> ATermTable
toATermTable at = fst $ addToTable at emptyATermTable
    where
    addToTable :: ATerm -> ATermTable -> (ATermTable,Int) 
    addToTable (AAppl s ats anns) att = 
        let (att1,ats')  = addToTableList ats att
            (att2,anns') = addToTableList anns att1
        in addATerm (ShAAppl s ats' anns') att2
    addToTable (AList ats anns)   att = 
        let (att1,ats')  = addToTableList ats att
            (att2,anns') = addToTableList anns att1
        in addATerm (ShAList ats' anns') att2
    addToTable (AInt i anns)      att = 
        let (att1,anns') = addToTableList anns att
        in addATerm (ShAInt i anns') att1
    addToTableList :: [ATerm] -> ATermTable -> (ATermTable,[Int])
    addToTableList []       att = (att,[])
    addToTableList (at1:ats) att = 
        let (att1,i)  = addToTable at1 att
            (att2,is) = addToTableList ats att1
        in (att2,i:is)

