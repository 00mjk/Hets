{-# OPTIONS -fglasgow-exts #-}
module GradedML where

import GMPAS
import ModalLogic
import Lexer

data GMLrules = GMLR [Int] [Int]
  deriving Show
-- negative coeff first, positive after
data Coeffs = Coeffs [Int] [Int]
    deriving (Eq, Ord)
instance ModalLogic GML GMLrules where
--    orderIns _ = True
    flagML _ = Ang
    parseIndex = do n <- natural
                    return $ GML (fromInteger n)
    matchR r = let (q, w) = eccContent r
                   wrapR (x,y) = GMLR x y
               in map wrapR (ineqSolver q (2^w))
    guessClause (GMLR n p) = 
      let zn = zip n [1..length n]
          zp = zip p (map (+length n) [1..length p])
          f l x = let aux = psplit l ((sum.fst.unzip.fst) x)
                  in assoc aux ((snd.unzip.fst) x,(snd.unzip.snd) x)
      in foldl (++) [] (map (f zp) (split zn))
-------------------------------------------------------------------------------
{- associate the elements of l with x
 - @ param l : list of pairs of lists of integers
 - @ param u : pair of lists of integers
 - @ return : list of propositional clauses (associated and wrapped lists) -}
assoc :: [([Int], [Int])] -> ([Int], [Int]) -> [PropClause]
assoc l u = map ((\x y -> Pimplies ((snd x)++(snd y)) ((fst x)++(fst y))) u) l
{- spliting function
 - @ param l : list to be split
 - @ return : all pairs of lists which result by spliting l -}
split :: [a] -> [([a], [a])]
split l =
  case l of
    []  -> [([],[])]
    h:t -> let x = split t
           in [(h:(fst q),snd q)|q <- x] ++ [(fst q,h:(snd q))|q <- x]
{- splitting function for positive coefficients
 - @ param l : list to be split
 - @ param s : sum of the current to be counted elements (the ones in J)
 - @ return : all pairs of indexes of positive coefficients which are good -}
psplit :: (Num a, Ord a) => [(a, b)] -> a -> [([b], [b])]
psplit l s =
    if (s < 0)
    then case l of
           []  -> [([],[])]
           h:t -> if (s + (fst h) < 0)
                  then let aux1 = psplit t (s + (fst h))
                           aux2 = psplit t s
                       in [((snd h):(fst q),snd q)|q <- aux1] ++ 
                          [(fst q,(snd h):(snd q))|q <- aux2]
                  else let aux = psplit t s
                       in [(fst q,(snd h):(snd q))|q <- aux]
    else []
{- compute the size of a number as specified in the paper
 - @ param i : the given integer
 - @ return : the size of i -}
size :: Int -> Int
size i = ceiling (logBase 2 (fromIntegral (abs i + 1)) :: Double)
{- extract the content of the contracted clause
 - @ param (Mimplies n p) : contracted clause
 - @ return : the grade of the equivalent modal applications in the input param
 -            and the length of the inequality
 - left: negative signed grades; right: positive signed grades -}
eccContent :: ModClause GML -> (Coeffs, Int)
eccContent (Mimplies n p) =
  let getGrade x =
        case x of
          Mapp (Mop (GML i) Angle) _ -> i
          _                          -> error "GradedML.getGrade"
      l1 = map (\x -> - x - 1) (map getGrade n)      -- coeff for negative r_i
      l2 = map getGrade p                            -- coeff for positive r_i
      w = 1 + (length l1) + (length l2) + sum (map size l1) + sum (map size l2)
  in (Coeffs l1 l2, w)
-------------------------------------------------------------------------------
{- generate all lists of given length and with elements between 1 and a limit
 - @ param n : fixed length
 - @ param lim : upper limit of elements
 - @ return : a list of all lists described above -}
negCands :: Int -> Int -> [[Int]]
negCands n lim =
  case n of
    0 -> [[]]
    _ -> [i:l| i <- [1..lim], l <- negCands (n-1) lim]
{- generate all lists of given length with elems between 1 and a limit such
 - that the side condition of Graded ML rule is satisfied
 - @ param n : fixed length
 - @ param lim : upper limit of elements
 - @ param s : sum (negative) which is previously computed and gets increased
 - @ param p : positive coefficients
 - @ return : list of all lists described above -}
posCands :: Int -> Int -> Int -> [Int] -> [[Int]]
posCands n lim s p =
 case n of
  0 -> [[]]
  _ -> [i:l|
        i<-[1..(min lim (floor (fromIntegral (abs s)/fromIntegral (head p)::Double)))],
        l <- (posCands (n-1) lim (s + i*(head p)) (tail p))]
{- gives all solutions in (1,lim) of the inequality with coeff n and p
 - @ param (Coeff n p) : negative and positive coefficients
 - @ param lim : limit for solution searching
 - @ return : solutions of the inequality, each stored as a pair -}
ineqSolver :: Coeffs -> Int -> [([Int],[Int])]
ineqSolver (Coeffs n p) lim = 
  let x = negCands (length n) lim
      linComb l1 l2 =
        if (l1 == [])||(l2==[])
        then 0
        else (head l1)*(head l2) + linComb (tail l1) (tail l2)
  in [(a,b)| a <- x, b <- posCands (length p) lim (linComb a n) p]
-------------------------------------------------------------------------------
