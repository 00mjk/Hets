module HasCASLModul where
import Prelude (undefined, Show)
 
type Pred a = a -> ()
 
type Unit = ()
 
data A__2_T_2 = A__2_T_2
              deriving Show
 
data A__2_M_M_G_2 = A__2_M_M_G_2
                  deriving Show
 
data A__2_M_M_G_Q_2 = A__2_M_M_G_Q_2
                    deriving Show
 
data A__2_M_G_2 = A__2_M_G_2
                deriving Show
 
data A__2_M_G_Q_2 = A__2_M_G_Q_2
                  deriving Show
 
data A_bool = True
            | False
            deriving Show
 
_2_S_B_2 :: ((), ()) -> ()
_2_S_B_2 = undefined
 
_2_L_R_G_2 :: ((), ()) -> ()
_2_L_R_G_2 = undefined
 
_2_R_2 :: (a, a) -> ()
_2_R_2 = undefined
 
_2_R_G_2 :: ((), ()) -> ()
_2_R_G_2 = undefined
 
_2_Re_R_2 :: (a, a) -> ()
_2_Re_R_2 = undefined
 
_2_B_S_2 :: ((), ()) -> ()
_2_B_S_2 = undefined
 
_2if_2 :: ((), ()) -> ()
_2if_2 = undefined
 
_2when_2else_2 :: (a, (), a) -> a
_2when_2else_2 = undefined
 
a :: A_bool
a = True
 
b2 :: A_bool -> A_bool
b2 = \ x -> (x :: A_bool)
 
b :: A_bool
b = let x = True
        y = False
        z = (x :: A_bool)
      in True
 
def_2 :: a -> ()
def_2 = undefined
 
false :: ()
false = undefined
 
if_2then_2else_2 :: ((), a, a) -> a
if_2then_2else_2 = undefined
 
not_2 :: () -> ()
not_2 = undefined
 
notA :: A_bool
notA
  = case a of
        True -> False
        False -> True
 
true :: ()
true = undefined
