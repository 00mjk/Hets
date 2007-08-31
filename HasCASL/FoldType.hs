{- |
Module      :  $Header$
Description :  fold functions for types
Copyright   :  (c) Christian Maeder and Uni Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

folding types
-}

module HasCASL.FoldType where

import HasCASL.As
import Common.Id
import qualified Data.Set as Set
import Data.List as List

data FoldTypeRec a = FoldTypeRec
  { foldTypeName :: Type -> Id -> RawKind -> Int -> a
  , foldTypeAppl :: Type -> a -> a -> a
  , foldExpandedType :: Type -> a -> a -> a
  , foldTypeAbs :: Type -> TypeArg -> a -> Range -> a
  , foldKindedType :: Type -> a -> (Set.Set Kind) -> Range -> a
  , foldTypeToken :: Type -> Token -> a
  , foldBracketType :: Type -> BracketKind -> [a] -> Range -> a
  , foldMixfixType :: Type -> [a] -> a }

mapTypeRec :: FoldTypeRec Type
mapTypeRec = FoldTypeRec
  { foldTypeName = \ _ -> TypeName
  , foldTypeAppl = \ _ -> TypeAppl
  , foldExpandedType = \ _ -> ExpandedType
  , foldTypeAbs = \ _ -> TypeAbs
  , foldKindedType = \ _ -> KindedType
  , foldTypeToken = \ _ -> TypeToken
  , foldBracketType = \ _ -> BracketType
  , foldMixfixType = \ _ -> MixfixType }

foldType :: FoldTypeRec a -> Type -> a
foldType r t = case t of
    TypeName i k c -> foldTypeName r t i k c
    TypeAppl t1 t2 -> foldTypeAppl r t (foldType r t1) $ foldType r t2
    ExpandedType t1 t2 -> foldExpandedType r t (foldType r t1) $ foldType r t2
    TypeAbs a ty p -> foldTypeAbs r t a (foldType r ty) p
    KindedType ty ks p -> foldKindedType r t (foldType r ty) ks p
    TypeToken tok -> foldTypeToken r t tok
    BracketType k ts p -> foldBracketType r t k (map (foldType r) ts) p
    MixfixType ts -> foldMixfixType r t $ map (foldType r) ts

-- | recursively substitute type alias names within a type
replAlias :: (Id -> RawKind -> Int -> Type) -> Type -> Type
replAlias m = foldType mapTypeRec
    { foldTypeName = \ _ -> m
    , foldExpandedType = \ (ExpandedType t1 _) r1 r2 -> case (t1, r1) of
        (TypeName _ _ _, ExpandedType t3 _) | t1 == t3 ->
            ExpandedType t1 r2
        _ -> ExpandedType r1 r2 }

-- | recursively substitute type variable names within a type
replTypeVar :: (Id -> RawKind -> Int -> Type) -> Type -> Type
replTypeVar m = foldType mapTypeRec
  { foldTypeName = \ _ -> m
  , foldTypeAbs = \ (TypeAbs v1@(TypeArg i _ _ _ c _ _) ty p) _ _ _ ->
        TypeAbs v1 (replTypeVar ( \ j k n -> (if (j, n) == (i, c) then
                      TypeName else m) j k n) ty) p }

-- | the type name components of a type
leaves :: (Int -> Bool) -> Type -> [(Int, (Id, RawKind))]
leaves b = foldType FoldTypeRec
  { foldTypeName = \ _ i k c -> if b c then [(c, (i, k))] else []
  , foldTypeAppl = \ _ t1 t2 -> List.union t1 t2
  , foldExpandedType = \ _ _ t2 -> t2
  , foldTypeAbs = \ _ (TypeArg i _ _ r c _ _) ty _ ->
        List.delete (c, (i, r)) ty
  , foldKindedType = \ _ ty _ _ -> ty
  , foldTypeToken = \ _ _ -> error "leaves.foldTypeToken"
  , foldBracketType = \ _ _ _ _ -> error "leaves.foldBracketType"
  , foldMixfixType = \ _ -> error "leaves.foldMixfixType" }
