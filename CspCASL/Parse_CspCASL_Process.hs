{- |
Module      :  $Id$
Description :  Parser for CspCASL processes
Copyright   :  (c)
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  a.m.gimblett@swan.ac.uk
Stability   :  experimental
Portability :

Parser for CSP-CASL processes.

-}

module CspCASL.Parse_CspCASL_Process (
    channel_name,
    comm_type,
    csp_casl_sort,
    csp_casl_process,
    event_set,
    process_name,
    var,
) where

import Text.ParserCombinators.Parsec (sepBy, try, (<|>))

import CASL.AS_Basic_CASL (FORMULA, SORT, TERM, VAR)
import qualified CASL.Formula
import Common.AnnoState (AParser, asKey)
import Common.Id
import Common.Keywords
import Common.Lexer ((<<), commaSep1, commaT, cParenT, oParenT)
import Common.Token (parseId, sortId, varId)

import CspCASL.AS_CspCASL_Process
import CspCASL.CspCASL_Keywords

csp_casl_process :: AParser st PROCESS
csp_casl_process = cond_proc <|> par_proc

cond_proc :: AParser st PROCESS
cond_proc = do ift <- asKey ifS
               f <- formula
               asKey thenS
               p <- csp_casl_process
               asKey elseS
               q <- csp_casl_process
               return (ConditionalProcess f p q (compRange ift q))

par_proc :: AParser st PROCESS
par_proc = do cp <- choice_proc
              p <- par_proc' cp
              return p

par_proc' :: PROCESS -> AParser st PROCESS
par_proc' lp =
    do     asKey interleavingS
           rp <- choice_proc
           p <- par_proc' (Interleaving lp rp (compRange lp rp))
           return p
    <|> do asKey synchronousS
           rp <- choice_proc
           p <- par_proc' (SynchronousParallel lp rp (compRange lp rp))
           return p
    <|> do asKey genpar_openS
           es <- event_set
           asKey genpar_closeS
           rp <- choice_proc
           p <- par_proc' (GeneralisedParallel lp es rp (compRange lp rp))
           return p
    <|> do asKey alpar_openS
           les <- event_set
           asKey alpar_sepS
           res <- event_set
           asKey alpar_closeS
           rp <- choice_proc
           p <- par_proc' (AlphabetisedParallel lp les res rp (compRange lp rp))
           return p
    <|> return lp

choice_proc :: AParser st PROCESS
choice_proc = do sp <- seq_proc
                 p <- choice_proc' sp
                 return p

choice_proc' :: PROCESS -> AParser st PROCESS
choice_proc' lp =
    do     asKey external_choiceS
           rp <- seq_proc
           p <- choice_proc' (ExternalChoice lp rp (compRange lp rp))
           return p
    <|> do asKey internal_choiceS
           rp <- seq_proc
           p <- choice_proc' (InternalChoice lp rp (compRange lp rp))
           return p
    <|> return lp

seq_proc :: AParser st PROCESS
seq_proc = do pp <- pref_proc
              p <- seq_proc' pp
              return p

seq_proc' :: PROCESS -> AParser st PROCESS
seq_proc' lp = do  asKey sequentialS
                   rp <- pref_proc
                   p <- seq_proc' (Sequential lp rp (compRange lp rp))
                   return p
               <|> return lp

pref_proc :: AParser st PROCESS
pref_proc = do     ipk <- asKey internal_choiceS
                   v <- var
                   asKey svar_sortS
                   s <- csp_casl_sort
                   asKey prefix_procS
                   p <- pref_proc
                   return (InternalPrefixProcess v s p (compRange ipk p))
            <|> do epk <- asKey external_choiceS
                   v <- var
                   asKey svar_sortS
                   s <- csp_casl_sort
                   asKey prefix_procS
                   p <- pref_proc
                   return (ExternalPrefixProcess v s p (compRange epk p))
            <|> do e <- try (event << asKey prefix_procS)
                   p <- pref_proc
                   return (PrefixProcess e p (compRange e p))
            <|> hid_ren_proc

hid_ren_proc :: AParser st PROCESS
hid_ren_proc = do pl <- prim_proc
                  p <- (hid_ren_proc' pl)
                  return p

hid_ren_proc' :: PROCESS -> AParser st PROCESS
hid_ren_proc' lp =
    do     asKey hiding_procS
           es <- event_set
           p <- (hid_ren_proc' (Hiding lp es (compRange lp es)))
           return p
    <|> do asKey ren_proc_openS
           rn <- renaming
           ck <- asKey ren_proc_closeS
           p <- (hid_ren_proc' (RenamingProcess lp rn (compRange lp ck)))
           return p
    <|> return lp

prim_proc :: AParser st PROCESS
prim_proc = do     try oParenT
                   p <- csp_casl_process
                   cParenT
                   return p
            <|> do rk <- asKey runS
                   oParenT
                   es <- event_set
                   cp <- cParenT
                   return (Run es (compRange rk cp))
            <|> do ck <- asKey chaosS
                   oParenT
                   es <- event_set
                   cp <- cParenT
                   return (Chaos es (compRange ck cp))
            <|> do dk <- asKey divS
                   return (Div (getRange dk))
            <|> do sk <- asKey stopS
                   return (Stop (getRange sk))
            <|> do sk <- asKey skipS
                   return (Skip (getRange sk))
            <|> do n <- (try process_name)
                   args <- procArgs
                   return (NamedProcess n args (compRange n args))

process_name :: AParser st PROCESS_NAME
process_name = varId csp_casl_keywords

channel_name :: AParser st CHANNEL_NAME
channel_name = varId csp_casl_keywords

comm_type :: AParser st COMM_TYPE
comm_type = varId csp_casl_keywords

-- List of arguments to a named process
procArgs :: AParser st [(TERM ())]
procArgs = do try oParenT
              es <- commaSep1 (CASL.Formula.term csp_casl_keywords)
              cParenT
              return es
           <|> return []

-- Sort IDs, excluding CspCasl keywords
csp_casl_sort :: AParser st SORT
csp_casl_sort = sortId csp_casl_keywords

event_set :: AParser st EVENT_SET
event_set = do cts <- comm_type `sepBy` commaT
               return (EventSet cts (getRange cts))

-- Events may be simple CASL terms or channel send/receives.

event :: AParser st EVENT
event = try chan_recv <|> try chan_nondet_send <|> try chan_send <|> term_event

chan_send :: AParser st EVENT
chan_send = do cn <- channel_name
               asKey chan_sendS
               t <- CASL.Formula.term csp_casl_keywords
               return (ChanSend cn t (getRange cn))

chan_nondet_send :: AParser st EVENT
chan_nondet_send = do cn <- channel_name
                      asKey chan_sendS
                      v <- var
                      asKey svar_sortS
                      s <- csp_casl_sort
                      return (ChanNonDetSend cn v s (compRange cn s))

chan_recv :: AParser st EVENT
chan_recv = do cn <- channel_name
               asKey chan_receiveS
               v <- var
               asKey svar_sortS
               s <- csp_casl_sort
               return (ChanRecv cn v s (compRange cn s))

term_event :: AParser st EVENT
term_event = do t <- CASL.Formula.term csp_casl_keywords
                return (TermEvent t (getRange t))

-- Formulas are CASL formulas.  We make our own wrapper around them
-- however.

formula :: AParser st (FORMULA ())
formula = do f <- CASL.Formula.formula csp_casl_keywords
             return f

-- Primitive renaming is done using an operator name or a predicate
-- name.  They're both Ids.  Separation between operator or predicate
-- (or some other non-applicable Id) must be a static analysis
-- problem.

renaming :: AParser st RENAMING
renaming = (parseId csp_casl_keywords) `sepBy` commaT

-- Variables come from CASL/Hets.

var :: AParser st VAR
var = varId csp_casl_keywords

-- Composition of ranges

compRange :: (PosItem a, PosItem b) => a -> b -> Range
compRange x y = (getRange x) `appRange` (getRange y)
