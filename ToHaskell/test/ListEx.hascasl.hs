{-

types:
List :: (*->*, data)

values:
myhead :: forall a . (List a) -> a
Cons :: forall a . (a, List a) -> List a
Nil :: forall a . List a

scope:
Prelude.Cons |-> Prelude.Cons, con of List
Prelude.List |-> Prelude.List, Type [Nil, Cons] []
Prelude.Nil |-> Prelude.Nil, con of List
Prelude.myhead |-> Prelude.myhead, Value
Cons |-> Prelude.Cons, con of List
List |-> Prelude.List, Type [Nil, Cons] []
Nil |-> Prelude.Nil, con of List
myhead |-> Prelude.myhead, Value
-}
module Dummy where
import Prelude (error, Show, Eq, Ord, Bool)
import MyLogic
myhead :: (List a) -> a
myhead (Cons (x_11_11, x_11_12)) = x_11_11
data List a = Nil | Cons !(a, List a)
