{- |
  test module similar to GUI_tests, but tests CMDL functions
-}
module Main where

import qualified Data.Map as Map
import qualified Data.Set as Set
import Common.Result
import Common.Id
import Common.AS_Annotation

import GUI.GenericATPState
import qualified Logic.Prover as LProver

import SoftFOL.Sign
import SoftFOL.ProveSPASS
import SoftFOL.ProveVampire
import SoftFOL.ProveMathServ
import SoftFOL.ProveDarwin

import System.IO (stdout, hSetBuffering, BufferMode(NoBuffering))
import System.Environment (getArgs)
import System.Exit

import qualified Control.Concurrent as Concurrent
import Control.Monad

-- * Definitions of test theories

sign1 :: SoftFOL.Sign.Sign
sign1 = emptySign 
  { sortMap = Map.insert (mkSimpleId "s") Nothing Map.empty
  , predMap = Map.fromList (map (\ (x,y) ->
      (mkSimpleId x, Set.singleton $ map mkSimpleId y))
        [("p",["s"]),("q",["s"]),("r",["s"]),("a",["s"])])}

term_x :: SPTerm
term_x = SPSimpleTerm (mkSPCustomSymbol "X")

axiom1 :: Named SPTerm
axiom1 = makeNamed "ax" (SPQuantTerm SPForall [term_x] (SPComplexTerm SPEquiv [SPComplexTerm (mkSPCustomSymbol "p") [term_x],SPComplexTerm (mkSPCustomSymbol "q") [term_x]]))

axiom2 :: Named SPTerm
axiom2 = makeNamed "ax2" (SPQuantTerm SPForall [term_x] (SPComplexTerm SPImplies [SPComplexTerm (mkSPCustomSymbol "q") [term_x],SPComplexTerm (mkSPCustomSymbol "r") [term_x]]))

axiom3 :: Named SPTerm
axiom3 = makeNamed "b$$-3" (SPQuantTerm SPForall [term_x] (SPComplexTerm SPImplies [SPComplexTerm (mkSPCustomSymbol "q") [term_x],SPComplexTerm (mkSPCustomSymbol "a") [term_x]]))

goal1 :: Named SPTerm
goal1 = (makeNamed "go" $ SPQuantTerm SPForall [term_x] (SPComplexTerm SPImplies [SPComplexTerm (mkSPCustomSymbol "q") [term_x],SPComplexTerm (mkSPCustomSymbol "p") [term_x] ])) { isAxiom = False }

goal2 :: Named SPTerm
goal2 = (makeNamed "go2" $ SPQuantTerm SPForall [term_x] (SPComplexTerm SPImplies [SPComplexTerm (mkSPCustomSymbol "p") [term_x],SPComplexTerm (mkSPCustomSymbol "r") [term_x] ])) { isAxiom = False }

goal3 :: Named SPTerm
goal3 = (makeNamed "go3" $ SPQuantTerm SPForall [term_x] (SPComplexTerm SPImplies [SPComplexTerm (mkSPCustomSymbol "p") [term_x],SPComplexTerm (mkSPCustomSymbol "a") [term_x] ])) { isAxiom = False }


theory1 :: LProver.Theory SoftFOL.Sign.Sign SPTerm ATP_ProofTree
theory1 = (LProver.Theory sign1 $ LProver.toThSens [axiom1,-- axiom2,
                         goal1,goal2])

theory2 :: LProver.Theory SoftFOL.Sign.Sign SPTerm ATP_ProofTree
theory2 = (LProver.Theory sign1 $ LProver.toThSens [axiom1,axiom2,axiom3,
                         goal1,goal2,goal3])

-- A more complicated theory including ExtPartialOrder from Basic/RelationsAndOrders.casl

signExt :: SoftFOL.Sign.Sign
signExt = emptySign {sortMap = {- Map.insert "Elem" Nothing -} Map.empty,
            funcMap = Map.fromList (map (\ (x, (y, z)) -> (mkSimpleId x,
                               Set.singleton (map mkSimpleId y, mkSimpleId z)))
                                    [("gn_bottom",([],"Elem")),
                                     ("inf",(["Elem", "Elem"],"Elem")),
                                     ("sup",(["Elem", "Elem"],"Elem"))]),
            predMap = Map.fromList (map (\ (x,y) -> (mkSimpleId x,
                                Set.singleton $ map mkSimpleId y))
                                        [ ("gn_defined",["Elem"]),
                                          ("p__LtEq__",["Elem", "Elem"])] )}

ga_nonEmpty :: Named SPTerm
ga_nonEmpty = makeNamed "ga_nonEmpty" SPQuantTerm {quantSym = SPExists, variableList = [SPSimpleTerm (mkSPCustomSymbol "X")], qFormula = SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X")]}}


ga_notDefBottom :: Named SPTerm
ga_notDefBottom = makeNamed "ga_notDefBottom" SPComplexTerm {symbol = SPNot, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_bottom", arguments = []}]}]}

ga_strictness :: Named SPTerm
ga_strictness = makeNamed "ga_strictness" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X_one"),SPSimpleTerm (mkSPCustomSymbol "X_two")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "inf", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_one"),SPSimpleTerm (mkSPCustomSymbol "X_two")]}]},SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_one")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_two")]}]}]}}

ga_strictness_one :: Named SPTerm
ga_strictness_one = makeNamed "ga_strictness_one" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X_one"),SPSimpleTerm (mkSPCustomSymbol "X_two")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "sup", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_one"),SPSimpleTerm (mkSPCustomSymbol "X_two")]}]},SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_one")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_two")]}]}]}}

ga_predicate_strictness :: Named SPTerm
ga_predicate_strictness = makeNamed "ga_predicate_strictness" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X_one"),SPSimpleTerm (mkSPCustomSymbol "X_two")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_one"),SPSimpleTerm (mkSPCustomSymbol "X_two")]},SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_one")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X_two")]}]}]}}

antisym :: Named SPTerm
antisym = makeNamed "antisym" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y")]}]},SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "X")]}]},SPComplexTerm {symbol = SPEqual, arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")]}]}]}}

trans :: Named SPTerm
trans = makeNamed "trans" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "Z")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y")]}]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Z")]}]},SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "Z")]}]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Z")]}]}]}}

refl :: Named SPTerm
refl = makeNamed "refl" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "X")]}]}}

inf_def_ExtPartialOrder :: Named SPTerm
inf_def_ExtPartialOrder = makeNamed "inf_def_ExtPartialOrder" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "Z")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y")]}]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Z")]}]},SPComplexTerm {symbol = SPEquiv, arguments = [SPComplexTerm {symbol = SPEqual, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "inf", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")]},SPSimpleTerm (mkSPCustomSymbol "Z")]},SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "Z"),SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "Z"),SPSimpleTerm (mkSPCustomSymbol "Y")]}]},SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "T")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "T")]},SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "T"),SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "T"),SPSimpleTerm (mkSPCustomSymbol "Y")]}]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "T"),SPSimpleTerm (mkSPCustomSymbol "Z")]}]}]}}]}]}]}}

sup_def_ExtPartialOrder :: Named SPTerm
sup_def_ExtPartialOrder = makeNamed "sup_def_ExtPartialOrder" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "Z")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y")]}]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Z")]}]},SPComplexTerm {symbol = SPEquiv, arguments = [SPComplexTerm {symbol = SPEqual, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "sup", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")]},SPSimpleTerm (mkSPCustomSymbol "Z")]},SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Z")]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "Z")]}]},SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "T")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "T")]},SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "T")]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "T")]}]},SPComplexTerm {symbol = mkSPCustomSymbol "p__LtEq__", arguments = [SPSimpleTerm (mkSPCustomSymbol "Z"),SPSimpleTerm (mkSPCustomSymbol "T")]}]}]}}]}]}]}}

ga_comm_sup :: Named SPTerm
ga_comm_sup = (makeNamed "ga_comm_sup" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y")]}]},SPComplexTerm {symbol = SPEqual, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "sup", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")]},SPComplexTerm {symbol = mkSPCustomSymbol "sup", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "X")]}]}]}}) { isAxiom = False }

ga_comm_inf :: Named SPTerm
ga_comm_inf = (makeNamed "ga_comm_inf" SPQuantTerm {quantSym = SPForall, variableList = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")], qFormula = SPComplexTerm {symbol = SPImplies, arguments = [SPComplexTerm {symbol = SPAnd, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "X")]},SPComplexTerm {symbol = mkSPCustomSymbol "gn_defined", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y")]}]},SPComplexTerm {symbol = SPEqual, arguments = [SPComplexTerm {symbol = mkSPCustomSymbol "inf", arguments = [SPSimpleTerm (mkSPCustomSymbol "X"),SPSimpleTerm (mkSPCustomSymbol "Y")]},SPComplexTerm {symbol = mkSPCustomSymbol "inf", arguments = [SPSimpleTerm (mkSPCustomSymbol "Y"),SPSimpleTerm (mkSPCustomSymbol "X")]}]}]}}) { isAxiom = False }

gone :: Named SPTerm
gone = (makeNamed "gone" $ SPSimpleTerm SPTrue) { isAxiom = False }

theoryExt :: LProver.Theory SoftFOL.Sign.Sign SPTerm ATP_ProofTree
theoryExt = (LProver.Theory signExt $ LProver.toThSens [ga_nonEmpty, ga_notDefBottom, ga_strictness, ga_strictness_one, ga_predicate_strictness, antisym, trans, refl, inf_def_ExtPartialOrder, sup_def_ExtPartialOrder, gone, ga_comm_sup, ga_comm_inf])

-- * Testing functions
main :: IO ()
main = do
     args <- getArgs
     hSetBuffering stdout NoBuffering
     if null args
        then runAllTests
        else case args of
               ["batch"] -> runBatchTests
               _ -> runMathServTest

exitOnBool :: Bool -> IO ()
exitOnBool b = if b
       then exitWith ExitSuccess
       else exitWith (ExitFailure 9)

runBatchTests :: IO ()
runBatchTests =
   sequence

   [runTestBatch2 True Nothing spassProveCMDLautomaticBatch "SPASS"
                 "[Test]Foo2" theory2
                 (zip ["go","go2","go3"] $ repeat (LProver.Proved Nothing))

   ,runTestBatch2 True Nothing darwinCMDLautomaticBatch "Darwin"
                 "[Test]Foo2" theory2
                 (zip ["go","go2","go3"] $ repeat (LProver.Proved (Just True)))

    ,runTestBatch2 True Nothing vampireCMDLautomaticBatch "Vampire"
                 "[Test]Foo2" theory2
                 (zip ["go","go2","go3"] $ repeat (LProver.Proved Nothing))

    ,runTestBatch2 True (Just 12) spassProveCMDLautomaticBatch "SPASS"
                 "[Test]ExtPartialOrder" theoryExt
                 (("gone",LProver.Proved Nothing) :
                  zip ["ga_comm_inf","ga_comm_sup"] (repeat LProver.Open))

    ,runTestBatch2 True (Just 12) darwinCMDLautomaticBatch "Darwin"
                 "[Test]ExtpartialOrder" theoryExt
                 (("gone", LProver.Proved (Just True)):
                 (zip ["ga_comm_sup"] (repeat LProver.Open)))

    ,runTestBatch2 True (Just 20) vampireCMDLautomaticBatch "Vampire"
                 "[Test]ExtPartialOrder" theoryExt
                  (zip ["gone","ga_comm_sup"] (repeat LProver.Open))
    ] >>= (exitOnBool . and)

runMathServTest :: IO ()
runMathServTest = do
    pass1 <-
        runTest mathServBrokerCMDLautomatic "MathServ" "[Test]Foo1" theory1
                [("go",LProver.Proved Nothing)]
    pass2 <-
        runTest vampireCMDLautomatic "Vampire" "[Test]Foo1" theory1
                [("go",LProver.Proved Nothing)]
    exitOnBool (pass1 && pass2)
{- |
  Main function doing all tests (combinations of theory and prover) in a row.
  Outputs status lines with information whether test passed or failed.
-}
runAllTests :: IO ()
runAllTests = do
   sequence
    [runTest spassProveCMDLautomatic "SPASS" "[Test]Foo1" theory1
                [("go",LProver.Proved Nothing)]
    ,runTest darwinCMDLautomatic "Darwin" "[Test]Foo1" theory1
                [("go",LProver.Proved (Just True))]
    ,runTest vampireCMDLautomatic "Vampire" "[Test]Foo1" theory1
                [("go",LProver.Proved Nothing)]
    ,runTest mathServBrokerCMDLautomatic "MathServ" "[Test]Foo1" theory1
                [("go",LProver.Proved Nothing)]

    ,runTest spassProveCMDLautomatic "SPASS" "[Test]Foo2" theory2
                [("go",LProver.Proved Nothing)]
    ,runTest darwinCMDLautomatic "Darwin" "[Test]Foo2" theory2
                [("go",LProver.Proved (Just True))]
    ,runTest vampireCMDLautomatic "Vampire" "[Test]Foo2" theory2
                [("go",LProver.Proved Nothing)]
    ,runTest mathServBrokerCMDLautomatic "MathServ" "[Test]Foo2" theory2
                [("go",LProver.Proved Nothing)]

    ,runTest spassProveCMDLautomatic "SPASS" "[Test]ExtPartialOrder" theoryExt
                [("gone",LProver.Proved Nothing)]
    ,runTest darwinCMDLautomatic "Darwin" "[Test]Foo2" theoryExt
                [("gone",LProver.Proved (Just True))]
    ,runTest vampireCMDLautomatic "Vampire" "[Test]ExtPartialOrder" theoryExt
                [("gone",LProver.Open)]
    ,runTest mathServBrokerCMDLautomatic "MathServ"
                "[Test]ExtPartialOrder" theoryExt
                [("gone",LProver.Proved Nothing)]

    ,runTestBatch Nothing spassProveCMDLautomaticBatch "SPASS"
                 "[Test]Foo1" theory1
                 [("go",LProver.Proved Nothing),
                  ("go2",LProver.Disproved)]
    ,runTestBatch Nothing darwinCMDLautomaticBatch "Darwin"
                 "[Test]Foo1" theory1
                 [("go",LProver.Proved (Just True)),
                  ("go2",LProver.Disproved)]
    ,runTestBatch Nothing vampireCMDLautomaticBatch "Vampire"
                 "[Test]Foo1" theory1
                 [("go",LProver.Proved Nothing),
                  ("go2",LProver.Disproved)]
    ,runTestBatch Nothing mathServBrokerCMDLautomaticBatch "MathServ"
                 "[Test]Foo1" theory1
                 [("go",LProver.Proved Nothing),
                  ("go2",LProver.Disproved)]

    ,runTestBatch Nothing spassProveCMDLautomaticBatch "SPASS"
                 "[Test]Foo2" theory2
                 (zip ["go","go2","go3"] $ repeat (LProver.Proved Nothing))
    ,runTestBatch Nothing darwinCMDLautomaticBatch "Darwin"
                 "[Test]Foo2" theory2
                 (zip ["go","go2","go3"] $ repeat (LProver.Proved (Just True)))
    ,runTestBatch Nothing vampireCMDLautomaticBatch "Vampire"
                 "[Test]Foo2" theory2
                 (zip ["go","go2","go3"] $ repeat (LProver.Proved Nothing))
    ,runTestBatch Nothing mathServBrokerCMDLautomaticBatch "MathServ"
                 "[Test]Foo2" theory2
                 (zip ["go","go2","go3"] $ repeat (LProver.Proved Nothing))

    ,runTestBatch (Just 12) spassProveCMDLautomaticBatch "SPASS"
                 "[Test]ExtPartialOrder" theoryExt
                 (("gone",LProver.Proved Nothing) :
                  zip ["ga_comm_inf","ga_comm_sup"] (repeat LProver.Open))
    ,runTestBatch (Just 20) darwinCMDLautomaticBatch "Darwin"
                 "[Test]ExtpartialOrder" theoryExt
                 (("gone", LProver.Proved (Just True)):
                 (zip ["ga_comm_sup"] (repeat LProver.Open)))
    ,runTestBatch (Just 20) vampireCMDLautomaticBatch "Vampire"
                 "[Test]ExtPartialOrder" theoryExt
                  (zip ["gone","ga_comm_sup"] (repeat LProver.Open))
    ,runTestBatch (Just 20) mathServBrokerCMDLautomaticBatch "MathServ"
                 "[Test]ExtPartialOrder" theoryExt
                 (("gone",LProver.Proved Nothing) :
                  zip ["ga_comm_inf","ga_comm_sup"] (repeat LProver.Open))
    ] >>= (exitOnBool . and)

{- |
  Runs a CMDL automatic function (given as parameter) over a given theory.
  The result will be output as status message.
-}
runTest :: (String
            -> LProver.Tactic_script
            -> LProver.Theory Sign Sentence ATP_ProofTree
            -> IO (Result ([LProver.Proof_status ATP_ProofTree]))
           )
        -> String -- ^ prover name for proof status in case of error
        -> String -- ^ theory name
        -> LProver.Theory Sign Sentence ATP_ProofTree
        -> [(String,LProver.GoalStatus)] -- ^ list of expected results
        -> IO Bool
runTest runCMDLProver prName thName th expStatus = do
    putStrLn $ "Trying " ++ thName ++ "(automatic) with prover " ++ prName ++ " ... "
    putStrLn $ show $ ATPTactic_script { ts_timeLimit = 20, ts_extraOpts = [] }
    m_result <- runCMDLProver
                           thName
                           (LProver.Tactic_script (show $ ATPTactic_script {
                              ts_timeLimit = 20, ts_extraOpts = [] }))
                           th
    stResult <- maybe (return [LProver.openProof_status ""
                                         prName (ATP_ProofTree "")])
                      return (maybeResult m_result)
    putStrLn $ if (succeeded stResult expStatus)
                 then "passed"
                 else ("failed\n"++ (unlines $ map show $ diags m_result))
    return (succeeded stResult expStatus)

{- |
  Runs a CMDL automatic batch function (given as parameter) over a given
  theory. The result will be output as status message.
-}
runTestBatch :: Maybe Int -- ^ seconds to pass before thread will be killed
              -> (Bool
                  -> Bool
                  -> Concurrent.MVar
                       (Result [LProver.Proof_status ATP_ProofTree])
                  -> String
                  -> LProver.Tactic_script
                  -> LProver.Theory Sign Sentence ATP_ProofTree
                  -> IO (Concurrent.ThreadId,Concurrent.MVar ())
                 )
              -> String -- ^ prover name
              -> String -- ^ theory name
              -> LProver.Theory Sign Sentence ATP_ProofTree
              -> [(String,LProver.GoalStatus)] -- ^ list of expected results
              -> IO Bool
runTestBatch waitsec runCMDLProver prName thName th expStatus =
    runTestBatch2 False waitsec runCMDLProver prName thName th expStatus
{- |
  Runs a CMDL automatic batch function (given as parameter) over a given
  theory. The result will be output as status message.
-}
runTestBatch2 :: Bool -- ^ True means try to read intermediate results
              -> Maybe Int -- ^ seconds to pass before thread will be killed
              -> (Bool
                  -> Bool
                  -> Concurrent.MVar
                       (Result [LProver.Proof_status ATP_ProofTree])
                  -> String
                  -> LProver.Tactic_script
                  -> LProver.Theory Sign Sentence ATP_ProofTree
                  -> IO (Concurrent.ThreadId,Concurrent.MVar ())
                 )
              -> String -- ^ prover name
              -> String -- ^ theory name
              -> LProver.Theory Sign Sentence ATP_ProofTree
              -> [(String,LProver.GoalStatus)] -- ^ list of expected results
              -> IO Bool
runTestBatch2 intermRes waitsec runCMDLProver prName thName th expStatus = do
    putStr $ "Trying " ++ thName ++ "(automaticBatch"++
           (if intermRes then " reading intermediate results" else "")++
           ") with prover " ++ prName ++ " ... "
    resultMVar <- if intermRes
                  then Concurrent.newEmptyMVar
                  else Concurrent.newMVar (return [])
    (threadID, mvar) <- runCMDLProver
                            False False resultMVar thName
                            (LProver.Tactic_script (show $ ATPTactic_script {
                               ts_timeLimit = 10, ts_extraOpts = [] }))
                            th
    maybe (return ()) (\ ws -> do
             Concurrent.threadDelay (ws*1000000)
             Concurrent.killThread threadID) waitsec
    (stResult,diaStr):: ([LProver.Proof_status ATP_ProofTree],String)
       <- if intermRes
        then do -- reading intermediate results
          iResMV <- Concurrent.newMVar []
          putStrLn ""
          let isReady = do
                mReady <- Concurrent.tryTakeMVar mvar
                maybe (return True)
                      (const $ Concurrent.putMVar mvar () >> return False)
                      mReady
              waitForEachResult = do
                -- Concurrent.yield
                mRes <- Concurrent.takeMVar resultMVar
                oldRes <- Concurrent.takeMVar iResMV
                putStrLn (unlines $ map show $ diags mRes)
                newRes <- maybe (return [])
                      (mapM (\ res -> do
                               putStrLn $ "Proof status of goal \""++
                                        LProver.goalName res++ "\": "++
                                        show (LProver.goalStatus res)
                               return res))
                      (maybeResult mRes)
                Concurrent.putMVar iResMV (oldRes++newRes)
                isReady
          -- external reader thread
          Concurrent.forkIO (
                        foldM_ (\ run ac ->
                                   if run then ac
                                   else return False) True $
                              map (const waitForEachResult) expStatus)
          -- wait for prover to complete
          Concurrent.takeMVar mvar
          mmRes <- Concurrent.tryTakeMVar resultMVar
          mRes <- maybe (return $ return [])
                        (\mR -> do putStrLn (unlines $ map show $ diags mR)
                                   return mR)
                        mmRes
          res <- Concurrent.takeMVar iResMV
          putStr "... "
          return (res++maybe [] id (maybeResult mRes),"")
      else do -- only read at the end of a batch run
        Concurrent.takeMVar mvar
        m_result <- Concurrent.takeMVar resultMVar
        return ( maybe [] id (maybeResult m_result)
               , (unlines $ map show $ diags m_result)++"\n"++ show m_result)
    putStrLn $ if (succeeded stResult expStatus)
                   then "passed"
                   else ("failed\n" ++ diaStr)
    return (succeeded stResult expStatus)

{- |
  Checks if a prover run's result matches expected result.
-}
succeeded :: [LProver.Proof_status ATP_ProofTree]
          -> [(String,LProver.GoalStatus)]
          -> Bool
succeeded stResult expStatus =
    (length stResult == length expStatus)
    && (foldl (\b givenRes -> maybe False (==(LProver.goalStatus givenRes))
                                    (lookup (LProver.goalName givenRes)
                                            expStatus)
                              && b)
              True stResult)
