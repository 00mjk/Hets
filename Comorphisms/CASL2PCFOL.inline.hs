{- |
Module      :  $Header$
Copyright   :  (c) Zicheng Wang, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

   Coding out subsorting (SubPCFOL= -> PCFOL=), 
   following Chap. III:3.1 of the CASL Reference Manual
-}

{-
   testen mit
     make ghci
     :l Comorphisms/CASL2PCFOL.hs

   wenn es druch geht, dann in hets.hs einf�gen
     import Comorphisms.CASL2PCFOL
   und dann einchecken, wenn es durch geht (make hets)
     cvs commit
-}

module Comorphisms.CASL2PCFOL where

--import Test
import Logic.Logic
import Logic.Comorphism
import Common.Id
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import Common.AS_Annotation

-- CASL
import CASL.Logic_CASL 
import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.Morphism 

-- | Add injection, projection and membership symbols to a signature
encodeSig :: Sign f e -> Sign f e
encodeSig sig = error "encodeSig not yet implemented"
{- todo
   setRel sig angucken
   Liste von Paaren (s,s') daraus generieren (siehe toList aus Common/Lib/Rel.hs)
   zur�ckgeben
   sig {opMap = ...     ein Id "_inj" mit Typmenge { s->s' | s<=s'}
                     +  ein Id "_proj" mit Typmegen {s'->?s | s<=s' }
        predMap = ...   pro s einen neuen Id "_elem_s" einf�gen, mit entsprechender Typmenge ( alle  s' mit s<=s') 
       }
zu benutzen: Map.insert, supersortsOf, Set.fromList . map f . Set.toList
wobei f aus einer Sorte s' einen Typ s->s' erzeugt 
-}


generateAxioms :: Sign f e -> [Named (FORMULA f)]
generateAxioms sig = 
  concat 
  ([inlineAxioms CASL
     "  sorts s < s' \
      \ op inj : s->s' \
      \ forall x,y:s . inj(x)=e=inj(y) => x=e=y   %(ga_embedding_injectivity)% "++
    inlineAxioms CASL
     " sort s< s' \
      \ op pr : s'->?s ; inj:s->s' \
      \ forall x:s . pr(inj(x))=e=x           %(projection)% " ++
    inlineAxioms CASL
      " sort s<s' \
      \ op pr : s'->?s \
      \ forall x,y:s'. pr(x)=e=pr(y)=>x=e=y   %(projection_transitiv)% " ++
    inlineAxioms CASL
      " sort s \
      \ op inj : s->s \
      \ forall x:s . inj(x)=e=x               %(indentity)%"             
          | (s,s') <- rel2List]++               
   [inlineAxioms CASL
     " sort s<s';s'<s'' \
      \ op inj:s'->s'' ; inj: s->s' ; inj:s->s'' \
      \ forall x:s . inj(inj(x))=e=inj(x)      %(transitive)% "  
          |(s,s')<-rel2List,s''<-Set.toList(supersortsOf s' sig)])
               
          
  where x = mkSimpleId "x"
        y = mkSimpleId "y"
        inj = mkId [mkSimpleId "_inj"]
        pr=mkId [mkSimpleId "_pr"]
        rel2List=Rel.toList(sortRel sig)
        rel2Map=Rel.toMap(sortRel sig)
        
{-
inj((op f:s_1*...*s_n->s)(inj(x_1),...,inj(x_n))) = 
inj((op f:s'_1*...*s'_n->s')(inj(x_1),...,inj(x_n))) 

forall x[i]:s[i] . inj((op f:s[i]->s)(inj(x[i]))) = 



test1 :: [Named (FORMULA f)]
test1 = 
  inlineAxioms CASL
     "  sorts s_i, s', s'' \
      \ op inj:s_i -> s_i \
      \ op f:s_i->s' \
      \ op inj:s'->s'' \
      \ forall x_i:s_i . def inj((op f:s_i->s')(inj(x_i))) \
      \ forall x_i:s_i . def x_i /\\ def x_i"
   where x = [mkSimpleId "x",mkSimpleId "y"]
         s = [mkId [mkSimpleId "s_1"],mkId [mkSimpleId "s_2"]]
         s' = [mkId [mkSimpleId "s'"]]


test2 :: [Named (FORMULA f)]
test2  = 
  inlineAxioms CASL
     "  sorts s < s' \
      \ op inj : s->s' \
      \ forall x,y:s . inj(x)=inj(y) => x=y  %(ga_embedding_injectivity)% "
  where x = mkSimpleId "x"
        y = mkSimpleId "y"
        inj = mkId [mkSimpleId "_inj"]

-}

{- todo
  Axiome auf S. 407, oder RefMan S. 173

  einfacher evtl.: mit Hets erzeugen

library encode

spec sp =
       sorts s < s'
       op inj : s->s'
       op proj : s'->?s
       pred in_s : s'
       var x,y:s
       . inj(x)=inj(y) => x=y  %(ga_embedding_injectivity)%
end

und dann

sens <- getCASLSens "../CASL-lib/encode.casl"



*Main> sig <- getCASLSig "../CASL-lib/encode.casl"

<interactive>:1: Warning: Defined but not used: sig
Reading ../CASL-lib/encode.casl
Analyzing spec sp
Writing ../CASL-lib/encode.env
*Main> sig
Sign {sortSet = {s,s'}, 
sortRel = {(s,s')}, 
opMap = {inj:={OpType {opKind = Total, opArgs = [s], opRes = s'}}}, 
assocOps = {}, predMap = {}, varMap = {}, sentences = [], envDiags = [], extendedInfo = ()}
*Main> sens <- getCASLSens "../CASL-lib/encode.casl"

<interactive>:1: Warning: Defined but not used: sens
Reading ../CASL-lib/encode.casl
Analyzing spec sp
Writing ../CASL-lib/encode.env
*Main> sens
[NamedSen {senName = "ga_embedding_injectivity", 
sentence = Implication (Strong_equation (Sorted_term (Application (Qual_op_name inj (Total_op_type [s] s' []) []) 
[Sorted_term (Qual_var x s []) s []] []) s' []) 
(Sorted_term (Application (Qual_op_name inj (Total_op_type [s] s' []) []) 
[Sorted_term (Qual_var y s []) s []] []) s' []) [../CASL-lib/encode.casl:7.16])
 (Strong_equation (Sorted_term (Qual_var x s []) s []) (Sorted_term (Qual_var y s []) s []) 
 [../CASL-lib/encode.casl:7.28]) True [../CASL-lib/encode.casl:7.24]}]
*Main>

-}


encodeFORMULA :: Named (FORMULA f) -> Named (FORMULA f)
encodeFORMULA phi = error "encodeFORMULA not yet implemented"
