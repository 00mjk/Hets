{- |
Module      :  $Header$
Description :  folder description
Copyright   :  (c) Christian Maeder and Uni Bremen 2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable (except HasCASL.Logic_HasCASL)

This folder contains the files for HasCASL basic specs

 * "HasCASL.As"                 abstract syntax with derived position access

 * "HasCASL.AsToLe"             convert abstract syntax to local environment

 * "HasCASL.AsUtils"            utilities to access the abstract syntax

 * "HasCASL.ATC_HasCASL"        generated ATerm conversions

 * "HasCASL.Builtin"            predefined HasCASL identifiers

 * "HasCASL.ClassAna"           analyse class identifiers and declarations

 * "HasCASL.Constrain"          kind and subtype constraints for type checking

 * "HasCASL.DataAna"            analyse data types

 * "HasCASL.HToken"             extended lexical HasCASL tokens 

 * "HasCASL.LaTeX_HasCASL"      (still dummy) instances for printing latex

 * "HasCASL.Le"                 the local environment, i.e. signature

 * "HasCASL.Logic_HasCASL"      the instance for "Logic.Logic"

 * "HasCASL.MapTerm"            mapping terms according to a morphism

 * "HasCASL.Merge"              merging repeated declarations

 * "HasCASL.MinType"            choose a term with minimal type 

 * "HasCASL.MixAna"             mixfix analysis 

 * "HasCASL.Morphism"           morphisms (without class translations)

 * "HasCASL.OpDecl"             analyse operation declarations 

 * "HasCASL.ParseItem"          parse any items except terms

 * "HasCASL.ParseTerm"          parse terms and formulas 

 * "HasCASL.PrintAs"            pretty print instances for "HasCASL.As"

 * "HasCASL.PrintLe"            pretty print instances for "HasCASL.Le"

 * "HasCASL.ProgEq"             interpret special formulas as programs

 * "HasCASL.RawSym"             raw, i.e. only parsed, symbols and maps 

 * "HasCASL.RunMixfixParser"    test utility for mixfix terms

 * "HasCASL.RunStaticAna"       test utility for the whole static analysis 

 * "HasCASL.Sublogic"           sublogic stuff

 * "HasCASL.SymbItem"           syntactic symbols and symbol maps

 * "HasCASL.Symbol"             semantic, i.e. analysed, symbols 

 * "HasCASL.SymbolMapAnalysis"  see "CASL.SymbolMapAnalysis"

 * "HasCASL.TypeAna"            kind analysis of type terms

 * "HasCASL.TypeCheck"          type inference of terms

 * "HasCASL.TypeDecl"           analyse type declarations 

 * "HasCASL.Unify"              unification algorithm for types

 * "HasCASL.VarDecl"            analyse declarations of variables 

-}
module HasCASL where
