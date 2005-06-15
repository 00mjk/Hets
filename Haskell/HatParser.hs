{-| 
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable(multiple parameter class, functional dependency)

Wrapper for Haskell parsing.
   Parses Haskell declarations (not a whole module), for use
     in heterogeneous specifications
-}

module Haskell.HatParser (module P, HsDecls(..), hatParser) where

import AST4ModSys as P(toMod)
import DefinedNames as P(DefinedNames)
import Ents as P(Ent(Ent))
import HasBaseName as P(HasBaseName(getBaseName))
import HsConstants as P(mod_Prelude)
import HsDeclStruct as P
import HsModule as P (HsModuleI(HsModule))
import HsName as P (hsUnQual, HsName(UnQual))
import LexerOptions as P(lexerflags0)
import Lift as P(Lift(lift))
import Modules as P(inscope)
import MUtils as P(mapFst)
import Names as P(QualNames(getQualified), QName)
import NewPrettyPrint as P(pp)
import OrigTiMonad as P(withStdNames, inModule, extendts, 
                        extendkts, extendIEnv)
import ParseMonad as P(parseTokens)
import PNT as P(PNT(PNT))
import PPfeInstances()
import PrettyPrint2 as P(Printable)
import PropLexer as P(pLexerPass0)
import PropParser as P(parse)
import PropPosSyntax as P hiding(Id, HsName)
import ReAssocBase as P(getInfixes)
import ReAssocModule as P(reAssocModule)
import Relations as P(applyRel, minusRel, mapDom, emptyRel, Rel)
import ScopeModule as P(origName, scopeModule)
import SourceNames as P(fakeSN, SN(SN))
import TiClasses as P(TAssump, TypeCheckDecls(tcTopDecls), HasDefs(fromDefs))
import TiDefinedNames as P(definedType)
import TiInstanceDB as P(Instance)
import TiNames as P(ValueId(topName))
import TiPropDecorate as P(TiDecl, TiDecls)
import TiTypes as P(Kind, Scheme, Typing((:>:)), Assump, TypeInfo)
import TypedIds as P(IdTy(Value), HasNameSpace(namespace))
import UniqueNames as P(noSrcLoc, Orig(G), PN(PN))
import WorkModule as P(mkWM, WorkModuleI)

import Haskell.Wrapper
import Text.ParserCombinators.Parsec
import Common.PrettyPrint
import Common.Lib.Pretty
import Common.Result

instance PrettyPrint HsDecls where
     printText0 _ ds = 
         vcat (map (text . ((++) "\n") . pp) $ hsDecls ds)

data HsDecls = HsDecls { hsDecls :: [HsDeclI (SN HsName)] } deriving (Show, Eq)

hatParser :: GenParser Char st HsDecls
hatParser = do p <- getPosition 
               s <- hStuff
	       let (l, c) = (sourceLine p, sourceColumn p)
                   ts = pLexerPass0 lexerflags0 
                        (replicate (l-2) '\n' ++
                         "module Prelude where\n" ++
                         replicate (c-1) ' ' ++ s)
               case parseTokens P.parse (sourceName p) ts of
		           Result _ (Just (HsModule _ _ _ _ ds)) -> 
				     return $ HsDecls ds
			   Result ds Nothing -> unexpected 
                               ('\n' : unlines (map diagString ds)
                                 ++ "(in Haskell code after " ++ shows p ")")
