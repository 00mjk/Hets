{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2003 
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  experimental
Portability :  portable 

make static analysis checkable by RunParsers 

-}

module CASL.RunStaticAna where

import CASL.StaticAna
import CASL.Sign
import Common.AnnoState
import Common.AS_Annotation
import Common.GlobalAnnotations
import Common.Result
import CASL.Parse_AS_Basic
import CASL.AS_Basic_CASL

localAnalysis :: GlobalAnnos -> BASIC_SPEC () () () 
              -> Result (BASIC_SPEC () () ())
localAnalysis ga bs = 
        let Result ds ms = basicCASLAnalysis (bs, emptySign () , ga)
        in Result ds $ case ms of 
           Just (newBs, _difSig, _accSig, _sents) -> Just newBs
           _ -> Nothing

runAna :: GlobalAnnos -> AParser () (Result (BASIC_SPEC () () ()))
runAna ga = 
    do b <- basicSpec []
       return $ localAnalysis ga b

localAna :: GlobalAnnos -> BASIC_SPEC () () () -> Result (Sign () ())
localAna ga bs = 
    let Result ds ms = 
            basicCASLAnalysis (bs, emptySign () , ga)
        es = filter ((<= Error)  . diagKind) ds
        in case ms of 
           Just (_newBs, difSig, _accSig, _sents) -> Result es $ Just difSig
           Nothing -> Result ds Nothing

getSign :: GlobalAnnos -> AParser () (Result (Sign () ()))
getSign ga = 
    do b <- basicSpec []
       return $ localAna ga b

props :: GlobalAnnos -> BASIC_SPEC () () () -> Result [Named (FORMULA ())]
props ga bs = 
    let Result ds ms = 
            basicCASLAnalysis (bs, emptySign (), ga)
        es = filter ((<= Error)  . diagKind) ds
        in case ms of 
           Just (_newBs, _difSig, _accSig, sents) -> Result es $ Just sents
           Nothing -> Result ds Nothing

getProps :: GlobalAnnos -> AParser () (Result [Named (FORMULA ())])
getProps ga = 
    do b <- basicSpec []
       return $ props ga b
