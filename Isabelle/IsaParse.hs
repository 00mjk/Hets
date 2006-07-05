{- |
Module      :  $Header$
Copyright   :  (c) C. Maeder and Uni Bremen 2005-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

parse the outer syntax of an Isabelle theory file. The syntax is taken from
 <http://isabelle.in.tum.de/dist/Isabelle/doc/isar-ref.pdf> for Isabelle2005.
-}

module Isabelle.IsaParse
    (parseTheory
    , Body(..)
    , TheoryHead(..)
    , compatibleBodies) where

import Data.List
import Common.Lexer
import Text.ParserCombinators.Parsec
import qualified Common.Lib.Map as Map
import Isabelle.IsaConsts
import Common.Id
import Common.Result
import Common.DocUtils

latin :: Parser String
latin = single letter <?> "latin"

greek :: Parser String
greek = string "\\<" <++>
         option "" (string "^") -- isup
         <++> many1 letter <++> string ">" <?> "greek"

isaLetter :: Parser String
isaLetter = latin <|> greek

quasiletter :: Parser String
quasiletter = single (digit <|> prime <|> char '_' ) <|> isaLetter
              <?> "quasiletter"

restident :: Parser String
restident = flat (many quasiletter)

ident :: Parser String
ident = isaLetter <++> restident

longident :: Parser String
longident = ident <++> flat (many $ char '.' <:> ident)

symident :: Parser String
symident = many1 (oneOf "!#$&*+-/:<=>?@^_|~" <?> "sym") <|> greek

isaString :: Parser String
isaString = enclosedBy (flat $ many (single (noneOf "\\\"")
                                 <|> char '\\' <:> single anyChar))
            (char '\"')

verbatim :: Parser String
verbatim = plainBlock "{*" "*}"

nestComment :: Parser String
nestComment = nestedComment "(*" "*)"

nat :: Parser String
nat = many1 digit <?> "nat"

name :: Parser String
name = ident <|> symident <|> isaString <|> nat

nameref :: Parser String -- sort
nameref = longident <|> symident <|> isaString <|> nat

isaText :: Parser String
isaText = nameref <|> verbatim

typefree :: Parser String
typefree = prime <:> ident

indexsuffix :: Parser String
indexsuffix =  option "" (char '.' <:> nat)

typevar :: Parser String
typevar = try (string "?'") <++> ident <++> option "" (char '.' <:> nat)

typeP :: Parser Token
typeP = lexP typefree <|> lexP typevar <|> namerefP

var :: Parser String
var = try (char '?' <:> isaLetter) <++> restident <++> indexsuffix

term :: Parser String -- prop
term = var <|> nameref

isaSkip :: Parser ()
isaSkip = skipMany (many1 space <|> nestComment <?> "")

lexP :: Parser String -> Parser Token
lexP pa = bind (\ p s -> Token s (Range [p])) getPos $ pa << isaSkip

lexS :: String -> Parser String
lexS s = try (string s) << isaSkip

headerP :: Parser Token
headerP = lexS headerS >> lexP isaText

nameP :: Parser Token
nameP = lexP $ reserved isaKeywords name

namerefP :: Parser Token
namerefP = lexP $ reserved isaKeywords nameref

parname :: Parser Token
parname = lexS "(" >> lexP name << lexS ")"

-- | the theory part before and including the begin keyword with a context
data TheoryHead = TheoryHead
   { theoryname :: Token
   , imports :: [Token]
   , uses :: [Token]
   , context :: Maybe Token
   } deriving Eq

theoryHead :: Parser TheoryHead
theoryHead = do
    option () isaSkip
    option Nothing $ fmap Just headerP
    lexS theoryS
    th <- nameP
    is <- option [] (lexS importsS >> many nameP)
    us <- option [] (lexS usesS >> many (nameP <|> parname))
    lexS beginS
    oc <- option Nothing $ fmap Just nameP
    return $ TheoryHead th is us oc

commalist :: Parser a -> Parser [a]
commalist p = fmap fst $ p `separatedBy` lexS ","

parensP :: Parser a -> Parser a
parensP p = do
    lexS "("
    a <- p
    lexS ")"
    return a

bracketsP :: Parser a -> Parser a
bracketsP p = do
    lexS "["
    a <- p
    lexS "]"
    return a

bracesP :: Parser a -> Parser a
bracesP p = do
    lexS "{"
    a <- p
    lexS "}"
    return a

recordP :: Parser a -> Parser a
recordP p = do
    lexS "(|"
    a <- p
    lexS "|)"
    return a

locale :: Parser ()
locale = forget . parensP $ lexS "in" >> nameP

markupP :: Parser Token
markupP = choice (map lexS markups) >> option () locale >> lexP isaText

infixP :: Parser ()
infixP = forget $ choice (map lexS ["infix", "infixl", "infixr"])
         >> option () (forget $ lexP isaString) >> lexP nat

mixfixSuffix :: Parser ()
mixfixSuffix = forget $ lexP isaString
    >> option [] (bracketsP $ commalist $ lexP nat)
           >> option () (forget $ lexP nat)

structureL :: Parser ()
structureL = forget $ lexS structureS

genMixfix :: Bool -> Parser ()
genMixfix b = parensP $
    (if b then id else (<|> structureL)) $
        infixP <|> mixfixSuffix <|> (lexS "binder" >> mixfixSuffix)

mixfix :: Parser ()
mixfix = genMixfix False

atom :: Parser String
atom = var <|> typefree <|> typevar <|> nameref
        -- nameref covers nat and symident keywords

args :: Parser [Token]
args = many $ lexP atom

attributes :: Parser ()
attributes = forget . bracketsP . commalist $ namerefP >> args

lessOrEq :: Parser String
lessOrEq = lexS "<" <|> lexS "\\<subseteq>"

classdecl :: Parser [Token]
classdecl = do
    n <- nameP
    lessOrEq
    ns <- commalist namerefP
    return $ n : ns

classes :: Parser ()
classes = forget $ lexS classesS >> many1 classdecl

data Typespec = Typespec Token [Token]

typespec :: Parser Typespec
typespec = fmap (\ n -> Typespec n []) namerefP <|> do
    ns <- parensP (commalist typefreeP) <|> fmap (:[]) typefreeP
    n <- namerefP
    return $ Typespec n ns
    where typefreeP = lexP typefree

optinfix :: Parser ()
optinfix = option () $ parensP infixP

types :: Parser [Typespec]
types = lexS typesS >> many1 (typespec << (lexS "=" >> typeP >> optinfix))

typedecl :: Parser [Typespec]
typedecl = lexS typedeclS >> many1 (typespec << optinfix)

arity :: Parser [Token]
arity = fmap (:[]) namerefP <|> do
    ns <- parensP $ commalist namerefP
    n <- namerefP
    return $ n : ns

data Const = Const Token Token

typeSuffix :: Parser Token
typeSuffix = lexS "::" >> typeP

consts :: Parser [Const]
consts = lexS constsS >> many1 (bind Const nameP (typeSuffix
                                          << option () mixfix))

vars :: Parser ()
vars = many1 nameP >> option () (forget typeSuffix)

andL :: Parser ()
andL = forget $ lexS andS

structs :: Parser ()
structs = parensP $ structureL << separatedBy vars andL

constdecl :: Parser [Const]
constdecl = do
    n <- nameP
    do t <- typeSuffix << option () mixfix
       return [Const n t]
     <|> (lexS "where" >> return [])
  <|> (mixfix >> return [])

constdef :: Parser ()
constdef = option () (forget thmdecl) << prop

constdefs :: Parser [[Const]]
constdefs = lexS constdefsS >> option () structs >>
            many1 (option [] constdecl << constdef)

axmdecl :: Parser Token
axmdecl = (nameP << option () attributes) << lexS ":"

prop :: Parser Token
prop = lexP $ reserved isaKeywords term

data Axiom = Axiom Token Token

axiomsP :: Parser [Axiom]
axiomsP = many1 (bind Axiom axmdecl prop)

defs :: Parser [Axiom]
defs = lexS defsS >> option "" (parensP $ lexS "overloaded") >>
       axiomsP

axioms :: Parser [Axiom]
axioms = lexS axiomsS >> axiomsP

thmbind :: Parser Token
thmbind = (nameP << option () attributes) <|> (attributes >> lexP (string ""))

selection :: Parser ()
selection = forget . parensP . commalist $
  natP >> option () (lexS "-" >> option () (forget natP))
  where natP = lexP nat

thmref :: Parser Token
thmref = namerefP << (option () selection >> option () attributes)

thmrefs :: Parser [Token]
thmrefs = many1 thmref

thmdef :: Parser Token
thmdef = try $ thmbind << lexS "="

thmdecl :: Parser Token
thmdecl = try $ thmbind << lexS ":"

theorems :: Parser ()
theorems = forget $ (lexS theoremsS <|> lexS lemmasS)
    >> option () locale
    >> separatedBy (option () (forget thmdef) >> thmrefs) andL

proppat :: Parser ()
proppat = forget . parensP . many1 $ lexP term

data Goal = Goal Token [Token]

props :: Parser Goal
props = bind Goal (option (mkSimpleId "") thmdecl)
        $ many1 (prop << option () proppat)

goal :: Parser [Goal]
goal = fmap fst $ separatedBy props andL

lemma :: Parser [Goal]
lemma = choice (map lexS [lemmaS, theoremS, corollaryS])
    >> option () locale >> goal -- longgoal ignored

instanceP :: Parser Token
instanceP =
    lexS instanceS >> namerefP << (lexS "::" << arity <|> lessOrEq << namerefP)

axclass :: Parser [Token]
axclass = lexS axclassS >> classdecl << many (axmdecl >> prop)

mltext :: Parser Token
mltext = lexS mlS >> lexP isaText

cons :: Parser [Token]
cons = bind (:) nameP (many typeP) << option () mixfix

data Dtspec = Dtspec Typespec [[Token]]

dtspec :: Parser Dtspec
dtspec = do
    option () $ forget $ try parname
    t <- typespec
    optinfix
    lexS "="
    cs <- fmap fst $ separatedBy cons $ lexS "|"
    return $ Dtspec t cs

datatype :: Parser [Dtspec]
datatype = lexS datatypeS >> fmap fst (separatedBy dtspec andL)

-- allow '.' sequences in unknown parts
anyP :: Parser String
anyP = atom <|> many1 (char '.')

-- allow "and", etc. in unknown parts
unknown :: Parser ()
unknown = skipMany1 $ forget (lexP $ reserved usedTopKeys anyP)
          <|> forget (recordP rec)
          <|> forget (parensP rec)
          <|> forget (bracketsP rec)
          <|> forget (bracesP rec)
          where rec = commalist $ unknown <|> forget (lexP anyP)

data BodyElem = Axioms [Axiom]
              | Goals [Goal]
              | Consts [Const]
              | Datatype [Dtspec]
              | Ignored

ignore :: Functor f => f a -> f BodyElem
ignore = fmap $ const Ignored

theoryBody :: Parser [BodyElem]
theoryBody = many $
    ignore typedecl
    <|> ignore types
    <|> fmap Datatype datatype
    <|> fmap Consts consts
    <|> fmap (Consts . concat) constdefs
    <|> fmap Axioms defs
    <|> ignore classes
    <|> ignore markupP
    <|> ignore theorems
    <|> fmap Axioms axioms
    <|> ignore instanceP
    <|> fmap Goals lemma
    <|> ignore axclass
    <|> ignore mltext
    <|> ignore (choice (map lexS ignoredKeys) >> skipMany unknown)
    <|> ignore unknown

-- | The axioms, goals, constants and data types of a theory
data Body = Body
    { axiomsF :: Map.Map Token Token
    , goalsF :: Map.Map Token [Token]
    , constsF :: Map.Map Token Token
    , datatypesF :: Map.Map Token ([Token], [[Token]])
    } deriving Show

addAxiom :: Axiom -> Map.Map Token Token -> Map.Map Token Token
addAxiom (Axiom n a) m = Map.insert n a m

addGoal :: Goal -> Map.Map Token [Token] -> Map.Map Token [Token]
addGoal (Goal n a) m = Map.insert n a m

addConst :: Const -> Map.Map Token Token -> Map.Map Token Token
addConst (Const n a) m = Map.insert n a m

addDatatype :: Dtspec -> Map.Map Token ([Token], [[Token]])
            -> Map.Map Token ([Token], [[Token]])
addDatatype (Dtspec (Typespec n ps) a) m = Map.insert n (ps, a) m

emptyBody :: Body
emptyBody = Body
    { axiomsF = Map.empty
    , goalsF = Map.empty
    , constsF = Map.empty
    , datatypesF = Map.empty
    }

concatBodyElems :: BodyElem -> Body -> Body
concatBodyElems x b = case x of
    Axioms l -> b { axiomsF = foldr addAxiom (axiomsF b) l }
    Goals l -> b { goalsF = foldr addGoal (goalsF b) l }
    Consts l -> b { constsF = foldr addConst (constsF b) l }
    Datatype l -> b { datatypesF = foldr addDatatype (datatypesF b) l }
    Ignored -> b

-- | parses a complete isabelle theory file, but skips i.e. proofs
parseTheory :: Parser (TheoryHead, Body)
parseTheory = bind (,)
    theoryHead (fmap (foldr concatBodyElems emptyBody) theoryBody)
    << lexS endS << eof

{- | Check that constants and data type are unchanged and that no axioms
was added and no theorem deleted. -}
compatibleBodies :: Body -> Body -> [Diagnosis]
compatibleBodies b1 b2 =
    diffMap "axiom" LT (axiomsF b2) (axiomsF b1)
    ++ diffMap "constant" EQ (constsF b2) (constsF b1)
    ++ diffMap "datatype" EQ (datatypesF b2) (datatypesF b1)
    ++ diffMap "goal" GT (goalsF b2) (goalsF b1)

diffMap :: (Ord a, Pretty a, PosItem a, Eq b, Show b)
          => String -> Ordering -> Map.Map a b -> Map.Map a b -> [Diagnosis]
diffMap msg o m1 m2 =
    let k1 = Map.keys m1
        k2 = Map.keys m2
        kd21 = k2 \\ k1
        kd12 = k1 \\ k2
    in if k1 == k2 then
    map ( \ (k, a) -> mkDiag Error
          (msg ++ " entry " ++ show a ++ " was changed for: ") k)
    $ Map.toList $
    Map.differenceWith ( \ a b -> if a == b then Nothing else
                                      Just a) m1 m2
    else let b = case o of
                   EQ -> null kd21
                   GT -> False
                   LT -> True
             kd = if b then kd12 else kd21
               in map ( \ k -> mkDiag Error
                    (msg ++ " entry illegally " ++
                         if b then "added" else "deleted") k) kd
