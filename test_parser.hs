module Main where

import System
import List

import Parsec
import ParsecPerm
import CaslLanguage
import Anno_Parser

import Id

import AS_Annotation
import Token

import Print_HetCASL

-- import Prepositional

-- # import LogicGraph

data TtT = TtT {f_::String , pY:: Pos} deriving Show {-! derive: update !-}

testP p s =  case (parse p "" s) of
	     Left err -> do{ putStr "parse error at "
			   ; print err
			   }
	     Right x  -> print x

testPL par inp = testP (do { whiteSpace
			   ; res <- par 
			   ; eof
			   ; return res
			   } ) inp

parseFile par name = do { inp <- readFile name
			;  case (parse (parL par) name inp) of
			  Left err -> do{ putStr "parse error at "
					; print err
					}
			  Right x  -> print $ printText0_eGA x
			}
    where parL p = do { whiteSpace
		      ; res <- p 
		      ; eof
		      ; return res
		      }

testFile par name = do { inp <- readFile name
		       ; sequence (map (testLine par) (lines inp))
		       }
    where testLine p line = do { putStr "** Input was: "
			       ; print line
			       ; putStr "** Result is: "
			       ; testPL p line
			       }

testFileC name = do { inp <- readFile name
		    ; sequence (map (testLine) (lines inp))
		    }
    where testLine line = do { putStr "** Input was: "
			     ; putStrLn line
			     ; putStr "** Result(KL) is: "
			     ; test_id casl_id line
			     ; putStr "** Result(CM) is: "
			     ; test_id parseId line
			       }

testData p s = parse (do {whiteSpace ; res <- p; eof ; return res}) "" s

test_id p inp = case (testData p inp) of 
		Left err -> print err
		Right id@(Id mix comp _) -> do { if comp == [] then 
					       putChar 'M' 
					       else 
					       putChar 'C'
					     ; putStr ": " 
					     ; putStrLn (showId id "") }

-- Comparing Id-Parser and presenting results
testFileCS name = do inp <- readFile name
		     ((ma,dif),rl) <- return $ 
				         mapAccumL testLine (0,0) (lines inp)
		     sequence rl
		     putStrLn $ "------\nMatched: " ++ show ma ++
		                "\nDiffs: " ++ show dif
		    
    where testLine (ma,dif) line = 
	      let res1 = testData casl_id line
		  res2 = testData parseId line
		  (ma1,dif1,out) = comp res1 res2 line
	      in ((ma+ma1,dif+dif1),out)

comp (Left err1) (Left err2) line = 
    (0,0,showDiff line (print err1) (print err2))
comp (Left err1) (Right id2) line = 
    (0,1,showDiff line (print err1) (printId id2))
comp (Right id1) (Left err2) line = 
    (0,1,showDiff line (printId id1) (print err2))
comp (Right id1) (Right id2) line = comp' id1 id2 line
    where comp' id1 id2 line =
	      if id1 == id2 then (1,0,putStr "")
	      else if showId id1 "" == showId id2 "" then diff_rep 
		   else diff_parse 
	  diff_parse = (0,1,putStrLn "Different Parses!" >> diff)
	  diff_rep = (1,0, putStrLn "Diferent Representations!" >> diff)
	  diff = showDiff line (printId id1) (printId id2) 

showDiff line out1 out2 =
    do putStr "** Input was: "
       putStrLn line
       putStr "** Result(KL) is: "
       out1
       putStr "** Result(CM) is: "
       out2

printId id@(Id mix comp _) = do if comp == [] then 
				   putChar 'M' 
				 else
			          do putChar 'C'
				     putStr ": " 
				     putStrLn (showId id "")


main = do { as <- getArgs
	  ; (p,files) <- return (extract_par as)
	  ; sequence (map (parseFile' p) files)  
	  }
    where extract_par = extract_par' "annotations" [] 
	  extract_par' p ac as = 
	      if as == [] then
		 error "*** No Filename or argument given"
	      else
	      case as of 
		      [s] -> (p,ac ++ as) 
		      x:ltl@(y:tl) -> if x == "-p" then
				      extract_par' y ac tl
				      else 
				      extract_par' p (ac++x:[]) (ltl)	 
	  parseFile' s = case s of
			 "annotations" -> parseFile annotations
			 "casl_id"     -> testFileC' 
			 "casl_id2"     -> testFileCS' 
			 otherwise     -> error ("*** unknown parser " ++ s)
	  testFileC' s = do { testFileC s
			    ; return ()
			    }
	  testFileCS' s = do { testFileCS s
			    ; return ()
			    }

	      
testId = testPL (sepBy casl_id semi) 
	 "__++__ ; __+*[y__,a_l'__,4]__ ; {__}[__] ; __a__b[__z]" 
