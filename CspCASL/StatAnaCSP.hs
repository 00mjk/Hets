{- |
Module      :  $Id$
Description :  static analysis for CspCASL
Copyright   :  (c) Markus Roggenbach, Till Mossakowski, Uni Bremen 2004-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  M.Roggenbach@swansea.ac.uk
Stability   :  provisional
Portability :  portable

Static analysis for CSP-CASL

-}

module CspCASL.StatAnaCSP where

import qualified Control.Monad as Monad
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as S

import CASL.AS_Basic_CASL (FunKind(..), SORT, TERM, VAR)
import CASL.Sign
import Common.AS_Annotation
import Common.Result
import Common.GlobalAnnotations
import qualified Common.Lib.Rel as Rel
import Common.Id (Id, simpleIdToId)
import Common.Lib.State
import Common.ExtSign

import CspCASL.AS_CspCASL
import CspCASL.AS_CspCASL_Process
import CspCASL.LocalTop (Obligation(..), unmetObs)
import CspCASL.Print_CspCASL ()
import CspCASL.SignCSP

basicAnalysisCspCASL :: (CspBasicSpec, CspSign, GlobalAnnos)
        -> Result (CspBasicSpec, ExtSign CspSign (), [Named ()])
basicAnalysisCspCASL (cc, sigma, _ga) = do
    let (_, accSig) = runState (ana_BASIC_CSP cc) sigma
    let ds = reverse $ envDiags accSig
    Result ds (Just ()) -- insert diagnostics
    return (cc, mkExtSign accSig, [])

ana_BASIC_CSP :: CspBasicSpec -> State CspSign ()
ana_BASIC_CSP cc = do checkLocalTops
                      mapM anaChanDecl (channels cc)
                      mapM anaProcItem (proc_items cc)
                      return ()

-- Analysis of local top elements

-- | Check CspCASL signature for local top elements in subsorts.
checkLocalTops :: State CspSign ()
checkLocalTops = do
    sig <- get
    let obs = unmetObs $ Rel.toList $ Rel.transClosure $ sortRel sig
    addDiags (map lteError obs)
    return ()

-- | Add diagnostic error for every unmet local top element obligation.
lteError :: Obligation SORT -> Diagnosis
lteError (Obligation x y z) = mkDiag Error msg ()
    where msg = ("local top element obligation ("
                 ++ (show x) ++ "<" ++ (show y) ++ "," ++ (show z)
                 ++ ") unfulfilled")

-- Analysis of channel declarations

anaChanDecl :: CHANNEL_DECL -> State CspSign CHANNEL_DECL
anaChanDecl (ChannelDecl chanNames chanSort) = do
    checkSorts [chanSort] -- check channel sort is known
    sig <- get
    let ext = extendedInfo sig
        oldChanMap = chans ext
    newChanMap <- Monad.foldM (anaChannelName chanSort) oldChanMap chanNames
    vds <- gets envDiags
    put sig { extendedInfo = ext { chans = newChanMap }
            , envDiags = vds
            }
    return (ChannelDecl chanNames chanSort)

anaChannelName :: SORT -> ChanNameMap -> CHANNEL_NAME ->
                    State CspSign ChanNameMap
anaChannelName s m chanName = do
    sig <- get
    if (show chanName) `S.member` (S.map show (sortSet sig))
      then do let err = "channel name already in use as a sort name"
              addDiags [mkDiag Error err chanName]
              return m
      else case Map.lookup chanName m of
             Nothing -> return (Map.insert chanName s m) -- insert new.
             Just e ->
               if e == s
                 then do let warn = "channel redeclared with same sort"
                         addDiags [mkDiag Warning warn chanName]
                         return m -- already declared with this sort.
                 else do let err = "channel declared with multiple sorts"
                         addDiags [mkDiag Error err chanName]
                         return m

-- Analysis of process items

anaProcItem :: PROC_ITEM -> State CspSign ()
anaProcItem procItem =
    case procItem of
      (Proc_Decl name argSorts alpha) -> anaProcDecl name argSorts alpha
      (Proc_Eq parmProcName procTerm) -> anaProcEq parmProcName procTerm

-- Analysis of process declarations

anaProcDecl :: PROCESS_NAME -> PROC_ARGS -> PROC_ALPHABET
            -> State CspSign ()
anaProcDecl name argSorts (ProcAlphabet commTypes _) = do
    sig <- get
    let ext = extendedInfo sig
        oldProcDecls = procSet ext
    newProcDecls <-
      if name `Map.member` oldProcDecls
        then do -- duplicate process declaration
                let err = "process name declared more than once"
                addDiags [mkDiag Error err name]
                return oldProcDecls
        else do -- new process declation
                checkSorts argSorts -- check argument sorts are known
                -- build alphabet: set of CommType values
                alpha <- Monad.foldM (anaCommType sig) S.empty commTypes
                let profile = (ProcProfile argSorts alpha)
                return (Map.insert name profile oldProcDecls)
    vds <- gets envDiags
    put sig { extendedInfo = ext {procSet = newProcDecls }
            , envDiags = vds
            }
    return ()

-- Analysis of process equations

anaProcEq :: PARM_PROCNAME -> PROCESS -> State CspSign ()
anaProcEq (ParmProcname pn vs) proc = do
    sig <- get
    let ext = extendedInfo sig
        procDecls = procSet ext
        prof = pn `Map.lookup` procDecls
    case prof of
      -- Only analyse a process if its name (and thus profile) is known
      Just (ProcProfile procArgs procAlpha) ->
        do gVars <- anaProcVars pn procArgs vs -- compute global vars
           termAlpha <- anaProcTerm proc procAlpha gVars Map.empty
           checkCommAlphaSub termAlpha procAlpha proc "process equation"
           return ()
      Nothing ->
        do addDiags [mkDiag Error "process equation for unknown process" pn]
           return ()
    vds <- gets envDiags
    put sig { envDiags = vds }
    return ()

-- Analysis of process variable names.

anaProcVars :: PROCESS_NAME -> [SORT] -> [VAR] -> State CspSign ProcVarMap
anaProcVars pn ss vs = do
    case (compare (length ss) (length vs)) of
       LT -> do addDiags [mkDiag Error "too many process arguments" pn]
                return Map.empty
       GT -> do addDiags [mkDiag Error "not enough process arguments" pn]
                return Map.empty
       EQ -> Monad.foldM anaProcVar Map.empty (zip vs ss)

anaProcVar :: ProcVarMap -> (VAR, SORT) -> State CspSign ProcVarMap
anaProcVar old (v, s) = do
    if v `Map.member` old
       then do addDiags [mkDiag Error "process arg declared more than once" v]
               return old
       else return (Map.insert v s old)

-- Analysis of process terms

anaProcTerm :: PROCESS -> CommAlpha -> ProcVarMap ->
               ProcVarMap -> State CspSign CommAlpha
anaProcTerm proc alpha gVars lVars = do
    case proc of
      NamedProcess name args _ ->
          do addDiags [mkDiag Debug "Named process" proc]
             al <- anaNamedProc proc name args (lVars `Map.union` gVars)
             return al
      Skip _ ->
          do addDiags [mkDiag Debug "Skip" proc]
             return S.empty
      Stop _ ->
          do addDiags [mkDiag Debug "Stop" proc]
             return S.empty
      Div _ ->
          do addDiags [mkDiag Debug "Div" proc]
             return S.empty
      Run es _ ->
          do addDiags [mkDiag Debug "Run" proc]
             comms <- anaEventSet es
             return comms
      Chaos es _ ->
          do addDiags [mkDiag Debug "Chaos" proc]
             comms <- anaEventSet es
             return comms
      PrefixProcess e p _ ->
          do addDiags [mkDiag Debug "Prefix" proc]
             (evComms, rcvMap) <- anaEvent e (lVars `Map.union` gVars)
             comms <- anaProcTerm p alpha gVars (rcvMap `Map.union` lVars)
             return (comms `S.union` evComms)
      InternalPrefixProcess v s p _ ->
          do addDiags [mkDiag Debug "Internal prefix" proc]
             checkSorts [s] -- check sort is known
             comms <- anaProcTerm p alpha gVars (Map.insert v s lVars)
             return (S.insert (CommTypeSort s) comms)
      ExternalPrefixProcess v s p _ ->
          do addDiags [mkDiag Debug "External prefix" proc]
             checkSorts [s] -- check sort is known
             comms <- anaProcTerm p alpha gVars (Map.insert v s lVars)
             return (S.insert (CommTypeSort s) comms)
      Sequential p q _ ->
          do addDiags [mkDiag Debug "Sequential" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             qComms <- anaProcTerm q alpha gVars Map.empty
             return (pComms `S.union` qComms)
      InternalChoice p q _ ->
          do addDiags [mkDiag Debug "InternalChoice" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             qComms <- anaProcTerm q alpha gVars lVars
             return (pComms `S.union` qComms)
      ExternalChoice p q _ ->
          do addDiags [mkDiag Debug "ExternalChoice" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             qComms <- anaProcTerm q alpha gVars lVars
             return (pComms `S.union` qComms)
      Interleaving p q _ ->
          do addDiags [mkDiag Debug "Interleaving" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             qComms <- anaProcTerm q alpha gVars lVars
             return (pComms `S.union` qComms)
      SynchronousParallel p q _ ->
          do addDiags [mkDiag Debug "Synchronous" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             qComms <- anaProcTerm q alpha gVars lVars
             return (pComms `S.union` qComms)
      GeneralisedParallel p es q _ ->
          do addDiags [mkDiag Debug "Generalised parallel" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             synComms <- anaEventSet es
             qComms <- anaProcTerm q alpha gVars lVars
             return (S.unions [pComms, qComms, synComms])
      AlphabetisedParallel p esp esq q _ ->
          do addDiags [mkDiag Debug "Alphabetised parallel" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             pSynComms <- anaEventSet esp
             checkCommAlphaSub pSynComms pComms proc "alphabetised parallel, left"
             qSynComms <- anaEventSet esq
             qComms <- anaProcTerm q alpha gVars lVars
             checkCommAlphaSub qSynComms qComms proc "alphabetised parallel, right"
             return (pComms `S.union` qComms)
      Hiding p es _ ->
          do addDiags [mkDiag Debug "Hiding" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             hidComms <- anaEventSet es
             return (pComms `S.union` hidComms)
      RenamingProcess p r _ ->
          do addDiags [mkDiag Debug "Renaming" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             renAlpha <- anaRenaming r
             return (pComms `S.union` renAlpha)
      ConditionalProcess _ p q _ ->
          do addDiags [mkDiag Debug "Conditional" proc]
             pComms <- anaProcTerm p alpha gVars lVars
             qComms <- anaProcTerm q alpha gVars lVars
             let fComms = S.empty -- XXX get formula sorts here
             return (S.unions [pComms, qComms, fComms])

anaNamedProc :: PROCESS -> PROCESS_NAME -> [TERM ()] -> ProcVarMap ->
                State CspSign CommAlpha
anaNamedProc proc pn terms procVars = do
    sig <- get
    let ext = extendedInfo sig
        procDecls = procSet ext
        prof = pn `Map.lookup` procDecls
    case prof of
      Just (ProcProfile _ permAlpha) ->
        do mapM (anaTermCspCASL procVars) terms
           -- XXX Check casting of terms 
           return permAlpha
      Nothing ->
        do addDiags [mkDiag Error "unknown process name" proc]
           return S.empty

-- Analysis of event sets and communication types

anaEventSet :: EVENT_SET -> State CspSign CommAlpha
anaEventSet (EventSet es _) = do
  sig <- get
  comms <- Monad.foldM (anaCommType sig) S.empty es
  vds <- gets envDiags
  put sig { envDiags = vds }
  return comms

anaCommType :: CspSign -> CommAlpha -> COMM_TYPE -> State CspSign CommAlpha
anaCommType sig alpha ct =
    if ctSort `S.member` (sortSet sig)
      then -- ct is a sort name; insert sort into alpha
        do return (S.insert (CommTypeSort ctSort) alpha)
      else -- ct not a sort name, so should be a channel name
        case Map.lookup ct (chans $ extendedInfo sig) of
          Just s -> -- ct is a channel name; insert typed chan name into alpha
                    return (S.insert (mkTypedChan ct s) alpha)
          Nothing -> do let err = "not a sort or channel name"
                        addDiags [mkDiag Error err ct]
                        return alpha
        where ctSort = simpleIdToId ct
              mkTypedChan c s = CommTypeChan $ TypedChanName c s

-- Analysis of events

anaEvent :: EVENT -> ProcVarMap -> State CspSign (CommAlpha, ProcVarMap)
anaEvent e vars = case e of
                    TermEvent t _ -> anaTermEvent t vars
                    ChanSend c t _ -> anaChanSend c t vars
                    ChanNonDetSend c v s _ -> anaChanBinding c v s
                    ChanRecv c v s _ -> anaChanBinding c v s

anaTermEvent :: (TERM ()) -> ProcVarMap ->
                State CspSign (CommAlpha, ProcVarMap)
anaTermEvent t vars = do
  anaTermCspCASL vars t
  let alpha = []   -- XXX Need to implement term sort computation
  return (S.fromList alpha, Map.empty)

anaChanSend :: CHANNEL_NAME -> (TERM ()) -> ProcVarMap ->
                State CspSign (CommAlpha, ProcVarMap)
anaChanSend c t vars = do
  sig <- get
  let ext = extendedInfo sig
  case c `Map.lookup` (chans ext) of
    Nothing -> do
      addDiags [mkDiag Error "unknown channel" c]
      return (S.empty, Map.empty)
    Just _ -> do -- XXX _ is to be chanSort
      anaTermCspCASL vars t
      -- XXX Need to implement term casting
      let alpha = []
      return (S.fromList alpha, Map.empty)

anaChanBinding :: CHANNEL_NAME -> VAR -> SORT ->
                   State CspSign (CommAlpha, ProcVarMap)
anaChanBinding c v s = do
  checkSorts [s] -- check sort is known
  sig <- get
  let ext = extendedInfo sig
  case c `Map.lookup` (chans ext) of
    Nothing -> do
      addDiags [mkDiag Error "unknown channel" c]
      return (S.empty, Map.empty)
    Just chanSort -> do
      if s `S.member` (subsorts chanSort)
        then do let alpha = [CommTypeSort s
                            ,CommTypeChan (TypedChanName c s)]
                let binding = [(v, s)]
                return (S.fromList alpha, Map.fromList binding)
        else do let err = "sort not a subsort of channel's sort"
                addDiags [mkDiag Error err s]
                return (S.empty, Map.empty)
            where subsorts = Rel.predecessors (sortRel sig)

-- Analysis of renaming and renaming items

anaRenaming :: RENAMING -> State CspSign CommAlpha
anaRenaming r = do al <- Monad.foldM anaRenamingItem S.empty r
                   return al

anaRenamingItem :: CommAlpha -> Id -> State CspSign CommAlpha
anaRenamingItem inAl ri = do
    totOps <- getBinOpsById ri Total
    if (not $ S.null totOps)
      then return (inAl `S.union` totOps)
      else do parOps <- getBinOpsById ri Partial
              if (not $ S.null parOps)
                then return (inAl `S.union` parOps)
                else do preds <- getBinPredsById ri
                        if (not $ S.null preds)
                          then return (inAl `S.union` preds)
                          else do let err = ("renaming item not a binary " ++
                                             "operation or predicate name")
                                  addDiags [mkDiag Error err ri]
                                  return inAl

-- |Get sorts of binary operations of the specified id and kind
getBinOpsById :: Id -> FunKind -> State CspSign (S.Set CommType)
getBinOpsById ri kind = do
    sig <- get
    let opsWithId = Map.findWithDefault S.empty ri (opMap sig)
        binOpsKind = S.filter (isBin kind) opsWithId
        cts = S.map CommTypeSort $ S.fold opSorts S.empty binOpsKind
    return cts
      where isBin k ot = (k == opKind ot) && (1 == (length (opArgs ot)))
            opSorts o inS = inS `S.union` (S.fromList ((opArgs o) ++ [opRes o]))

-- |Get sorts of binary predicates of the specified id and kind
getBinPredsById :: Id -> State CspSign (S.Set CommType)
getBinPredsById ri = do
    sig <- get
    let predsWithId = Map.findWithDefault S.empty ri (predMap sig)
        binPreds = S.filter isBin predsWithId
        cts = S.map CommTypeSort $ S.fold predSorts S.empty binPreds
    return cts
      where isBin ot = (2 == (length (predArgs ot)))
            predSorts p inS = inS `S.union` (S.fromList (predArgs p))

--isBin :: FunKind -> OpType -> Bool

-- Analysis of communication alphabet subsort-closed subset relationships.

checkCommAlphaSub :: CommAlpha -> CommAlpha -> PROCESS -> String ->
                     State CspSign ()
checkCommAlphaSub sub super proc context = do
  sig <- get
  let extras = ((closeCspCommAlpha sig sub) `S.difference`
                (closeCspCommAlpha sig super))
  if S.null extras
    then do return ()
    else do let err = ("Communication alphabet subset violations (" ++
                       context ++ "): " ++ (show $ S.toList extras))
            addDiags [mkDiag Error err proc]
            return ()

-- Analysis of term appearing in CspCASL context

anaTermCspCASL :: ProcVarMap -> (TERM ()) -> State CspSign ()
anaTermCspCASL _ _ = do return () -- XXX not yet implemented
