{- |
Module      :  $Header$
Description :  'ResultT' type and a monadic transformer instance
Copyright   :  (c) T. Mossakowski, C. Maeder, Uni Bremen 2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

'ResultT' type and a monadic transformer instance
-}

module Common.ResultT where

import Common.Result
import Control.Monad.Trans

newtype ResultT m a = ResultT { runResultT :: m (Result a) }

instance Monad m => Functor (ResultT m) where
    fmap f m = ResultT $ do
        r <- runResultT m
        return $ fmap f r

instance Monad m => Monad (ResultT m) where
    return a = ResultT $ return $ return a
    m >>= k = ResultT $ do
        r@(Result e v) <- runResultT m
        case v of
          Nothing -> return $ Result e Nothing
          Just a -> do
                s <- runResultT $ k a
                return $ joinResult r s
    fail s = ResultT $ return $ fail s

instance MonadTrans ResultT where
    lift m = ResultT $ do
        a <- m
        return $ return a

liftR :: Monad m => Result a -> ResultT m a
liftR = ResultT . return
