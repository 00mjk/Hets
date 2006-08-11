{- |
Module      :  $Header$
Copyright   :  (c) T. Mossakowski, C. Maeder, Uni Bremen 2005-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  till@tzi.de
Stability   :  provisional
Portability :  non-portable (various -fglasgow-exts extensions)

-- for coercion used in Grothendieck.hs and Analysis modules
-}

module Logic.Coerce where

import Logic.Logic
import Logic.Prover
import Common.Id
import Common.Result
import Common.AS_Annotation
import qualified Common.Lib.Set as Set
import Common.DynamicUtils
import ATC.Prover()

-- coercion using the language name
primCoerce :: (Typeable a, Typeable b, Language lid1, Language lid2,
          Monad m) => lid1 -> lid2 -> String -> a -> m b
primCoerce i1 i2 err a =
  if language_name i1 == language_name i2
     then return $ fromDyn (toDyn a) $ error "mcoerce"
     else fail (err1++"Logic "++ language_name i1 ++ " expected, but "
                ++ language_name i2 ++ " found")
  where err1 = if err=="" then "" else err++": "

unsafeCoerce :: (Typeable a, Typeable b, Language lid1, Language lid2)
               => lid1 -> lid2 -> a -> b
unsafeCoerce i1 i2 a = maybe (error "unsafeCoerce") id $ primCoerce i1 i2 "" a

coerceToResult :: (Typeable a, Typeable b, Language lid1, Language lid2) =>
           lid1 -> lid2 -> Range -> a -> Result b
coerceToResult i1 i2 pos a = adjustPos pos $ primCoerce i1 i2 "" a

coerceSublogic ::
   (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m)
   => lid1 -> lid2 -> String -> sublogics1 -> m sublogics2
coerceSublogic l1 l2 msg s1 = primCoerce l1 l2 msg s1

forceCoerceSublogic ::
   (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2)
   => lid1 -> lid2 -> sublogics1 -> sublogics2
forceCoerceSublogic l1 l2 s1 = unsafeCoerce l1 l2 s1

coerceSign ::
   (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String -> sign1 -> m sign2
coerceSign l1 l2 msg s1 = primCoerce l1 l2 msg s1

coerceBasicTheory ::
   (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String
            -> (sign1, [Named sentence1]) -> m (sign2, [Named sentence2])
coerceBasicTheory l1 l2 msg t1 = primCoerce l1 l2 msg t1

coerceTheory :: 
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
               sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
               sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String 
            -> Theory sign1 sentence1 proof_tree1
            -> m (Theory sign2 sentence2 proof_tree2)
coerceTheory l1 l2 msg t1 = primCoerce l1 l2 msg t1

coerceMorphism ::    
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String -> morphism1 -> m morphism2
coerceMorphism l1 l2 msg m1 = primCoerce l1 l2 msg m1

coerceSymbol ::
   (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2)
   => lid1 -> lid2 -> symbol1 -> symbol2
coerceSymbol l1 l2 s1 = unsafeCoerce l1 l2 s1

coerceSymbItemsList ::
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String -> [symb_items1] -> m [symb_items2]
coerceSymbItemsList l1 l2 msg m1 = primCoerce l1 l2 msg m1

coerceSymbMapItemsList ::
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String
      -> [symb_map_items1] -> m [symb_map_items2]
coerceSymbMapItemsList l1 l2 msg m1 = primCoerce l1 l2 msg m1

coerceBasicProof ::
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String
      -> Proof_status proof_tree1 -> m (Proof_status proof_tree2)
coerceBasicProof l1 l2 msg m1 = primCoerce l1 l2 msg m1

coerceSymbolSet ::
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String -> Set.Set symbol1 -> m (Set.Set symbol2)
coerceSymbolSet l1 l2 msg m1 = primCoerce l1 l2 msg m1

coerceRawSymbolMap ::
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String -> EndoMap raw_symbol1
      -> m (EndoMap raw_symbol2)
coerceRawSymbolMap l1 l2 msg m1 = primCoerce l1 l2 msg m1
