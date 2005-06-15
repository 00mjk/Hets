
{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2003
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable
    
String constants for CASL keywords to be used for parsing and printing

- all identifiers are mixed case (i.e. the keyword followed by  a capital S)

- see <http://www.cofi.info/Documents/CASL/Summary/> from 25 March 2001, 
  C.4 Lexical Syntax
-}


module Common.Keywords where

-- * context dependend keywords

-- | sub sort indicator
lessS :: String
lessS  = "<"

-- | modifier for 'existsS'
exMark :: String
exMark  = "!" 

-- | modifier for 'funS' or 'colonS'
quMark :: String 
quMark  = "?"  

-- ** type constructors
timesS,
  prodS,
  funS :: String
funS  = "->"
prodS  = "*"
timesS  = "\215"

-- * symbol keywords 
defnS,
  mapsTo,
  barS,
  cDot,
  dotS,
  colonS :: String 
colonS  = ":"
dotS  = "."
cDot  = "\183"
barS  = "|"
mapsTo  = "|->"
defnS  = "::="

-- ** equality symbols

-- | mind spacing i.e. in @e =e= e@
exEqual :: String
exEqual  = "=e="  

-- | also a definition indicator
equalS :: String
equalS  = "="

-- ** formula symbols
lOr,
  lAnd,
  negS,
  equivS,
  implS :: String
implS  = "=>"
equivS  = "<=>"
negS  = "\172"
lAnd  = "/\\"    
lOr  = "\\/"

-- * lower case letter keywords
withinS,
  withS,
  viewS,
  versionS,
  unitS,
  typeS,
  cotypeS,
  toS,
  thenS,
  specS,
  sortS,
  revealS,
  resultS,
  localS,
  logicS,
  libraryS,
  lambdaS,
  inS,
  idemS,
  hideS,
  givenS,
  getS,
  generatedS,
  cogeneratedS,
  fromS,
  cofreeS,
  freeS,
  fitS,
  forallS,
  existsS,
  endS,
  commS,
  closedS,
  opS,
  predS,
  varS,
  sS,
  axiomS,
  assocS,
  asS,
  archS,
  andS,
  whenS,
  trueS,
  notS,
  ifS,
  falseS,
  elseS,
  defS :: String

defS  = "def"
elseS  = "else"
falseS  = "false"
ifS  = "if"
notS  = "not"
trueS  = "true"
whenS  = "when"

andS  = "and"
archS  = "arch"
asS  = "as"
assocS  = "assoc"
axiomS  = "axiom"
sS  = "s" 
varS  = "var"
predS  = "pred"
opS  = "op"
closedS  = "closed"
commS  = "comm"
endS  = "end"
existsS  = "exists"
forallS  = "forall"
fitS  = "fit"
freeS  = "free"
cofreeS  = "cofree"
fromS  = "from"
generatedS  = "generated"
cogeneratedS = "cogenerated"
getS  = "get"
givenS  = "given" 
hideS  = "hide"
idemS  = "idem"
inS  = "in"
lambdaS  = "lambda"
libraryS  = "library"
localS  = "local"
logicS = "logic" -- new keyword
resultS  = "result"
revealS  = "reveal" 
sortS  = "sort"
specS  = "spec"
thenS  = "then"
toS  = "to"
typeS  = "type"
cotypeS = "cotype"
unitS  = "unit"
versionS  = "version"
viewS  = "view"
withS  = "with"
withinS  = "within"

refinementS, refinedS, behaviourallyS :: String
refinementS = "refinement"
refinedS = "refined"
behaviourallyS = "behaviourally"

viaS, dataS :: String
viaS = "via"
dataS = "data"
