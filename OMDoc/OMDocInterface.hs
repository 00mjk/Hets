{- |
Module      :  $Header$
Copyright   :  (c) Hendrik Iben, Uni Bremen 2005-2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  hiben@tzi.de
Stability   :  provisional
Portability :  portable

Model of a handpicked subset from OMDoc
-}
module OMDoc.OMDocInterface where

import qualified Network.URI as URI

import Data.Char

import qualified Data.Word as Word

omdocDefaultNamespace :: String
omdocDefaultNamespace = "http://www.mathweb.org/omdoc"

-- | OMDocRef is anyURI
type OMDocRef = URI.URI

-- | OMDocRefs modelled as a list
type OMDocRefs = [OMDocRef]

showURI::URI.URI->String
showURI uri = (URI.uriToString id uri) ""

-- Try to parse an URI (so Network.URI needs not be imported)
mkOMDocRef::String->Maybe OMDocRef
mkOMDocRef = URI.parseURIReference

mkSymbolRef::XmlId->OMDocRef
mkSymbolRef xid =
  case URI.parseURIReference ("#"++xid) of
    Nothing -> error "Invalid Symbol-Id!"
    (Just u) -> u

mkExtSymbolRef::XmlId->XmlId->OMDocRef
mkExtSymbolRef xcd xid =
  case URI.parseURIReference (xcd ++ "#" ++ xid) of
    Nothing -> error "Invalid Reference!"
    (Just u) -> u

{- OMDoc -}

-- | used for ids
type XmlId = String
-- | used for names, pcdata
type XmlString = String

-- | OMDoc
data OMDoc =
  OMDoc
    {
        omdocId :: XmlId
      , omdocTheories :: [Theory]
      , omdocInclusions :: [Inclusion]
    }
    deriving (Show)

addTheories::OMDoc->[Theory]->OMDoc
addTheories omdoc theories =
  omdoc
    {
      omdocTheories = (omdocTheories omdoc) ++ theories
    }

addInclusions::OMDoc->[Inclusion]->OMDoc
addInclusions omdoc inclusions =
  omdoc
    {
      omdocInclusions = (omdocInclusions omdoc) ++ inclusions
    }

-- Theory
data Theory =
  Theory
    {
        theoryId :: XmlId
      , theoryConstitutives :: [Constitutive]
      , theoryPresentations :: [Presentation]
      , theoryComment :: Maybe String
    }
    deriving Show

instance Eq Theory where
  t1 == t2 = (theoryId t1) == (theoryId t2)

instance Ord Theory where
  t1 `compare` t2 = (theoryId t1) `compare` (theoryId t2)

-- debug
showTheory::Theory->String
showTheory t = show (t { theoryPresentations = [] })

-- | Type (scope) of import
data ImportsType = ITLocal | ITGlobal
  deriving Show

-- | Imports (for Theory)
data Imports =
  Imports
    {
        importsFrom :: OMDocRef
      , importsMorphism :: Maybe Morphism
      , importsId :: Maybe XmlId
      , importsType :: ImportsType
      , importsConservativity :: Conservativity
    }
    deriving Show

-- | Presentation
data Presentation =
  Presentation 
    {
        presentationForId :: XmlId
      , presentationSystem :: Maybe XmlString
      , presentationUses :: [Use]
    }
    deriving (Show, Eq)

mkPresentationS::XmlId->XmlString->[Use]->Presentation
mkPresentationS forid presSystem = Presentation forid (Just presSystem)

mkPresentation::XmlId->[Use]->Presentation
mkPresentation forid = Presentation forid Nothing

addUse::Presentation->Use->Presentation
addUse pres use = pres { presentationUses = (presentationUses pres) ++ [use] }

-- | Use for Presentation
data Use =
  Use
    {
        useFormat :: XmlString
      , useValue :: String
    }
    deriving (Show, Eq)

mkUse::XmlString->String->Use
mkUse = Use

-- | SymbolRole for Symbol
data SymbolRole =
    SRType
  | SRSort
  | SRObject
  | SRBinder
  | SRAttribution
  | SRSemanticAttribution
  | SRError
  deriving Eq

instance Show SymbolRole where
  show SRType = "type"
  show SRSort = "sort"
  show SRObject = "object"
  show SRBinder = "binder"
  show SRAttribution = "attribution"
  show SRSemanticAttribution = "semantic-attribution"
  show SRError = "error"

instance Read SymbolRole where
  readsPrec _ s =
    case map toLower s of
      "type" -> [(SRType, [])]
      "sort" -> [(SRSort, [])]
      "object" -> [(SRObject, [])]
      "binder" -> [(SRBinder, [])]
      "attribution" -> [(SRAttribution, [])]
      "semantic-attribution" -> [(SRSemanticAttribution, [])]
      "error" -> [(SRError, [])]
      _ -> []

-- | Symbol
data Symbol =
  Symbol
    {
        symbolGeneratedFrom :: Maybe XmlId
      , symbolId :: XmlId
      , symbolRole :: SymbolRole
      , symbolType :: Maybe Type
    }
    deriving (Show)

mkSymbolE::Maybe XmlId->XmlId->SymbolRole->Maybe Type->Symbol
mkSymbolE = Symbol

mkSymbol::XmlId->SymbolRole->Symbol
mkSymbol xid sr = mkSymbolE Nothing xid sr Nothing

-- | Type
data Type =
  Type
    {
        typeSystem :: Maybe URI.URI
      , typeOMDocMathObject :: OMDocMathObject
    }
    deriving (Show)

mkType::Maybe OMDocRef->OMDocMathObject->Type
mkType = Type

{- |
  OMDoc Theory constitutive elements + convenience additions (ADT)
-}
data Constitutive =
    CAx Axiom
  | CDe Definition
  | CSy Symbol
  | CIm Imports
  | CAd ADT
  | CCo { conComCmt::String, conComCon::Constitutive }
  deriving Show

mkCAx::Axiom->Constitutive
mkCAx = CAx
mkCDe::Definition->Constitutive
mkCDe = CDe
mkCSy::Symbol->Constitutive
mkCSy = CSy
mkCIm::Imports->Constitutive
mkCIm = CIm
mkCAd::ADT->Constitutive
mkCAd = CAd
mkCCo::String->Constitutive->Constitutive
mkCCo = CCo

isAxiom::Constitutive->Bool
isAxiom (CAx {}) = True
isAxiom _ = False

isDefinition::Constitutive->Bool
isDefinition (CDe {}) = True
isDefinition _ = False

isSymbol::Constitutive->Bool
isSymbol (CSy {}) = True
isSymbol _ = False

isImports::Constitutive->Bool
isImports (CIm {}) = True
isImports _ = False

isADT::Constitutive->Bool
isADT (CAd {}) = True
isADT _ = False

isCommented::Constitutive->Bool
isCommented (CCo {}) = True
isCommented _ = False

getIdsForPresentation::Constitutive->[XmlId]
getIdsForPresentation (CAx a) = [axiomName a]
getIdsForPresentation (CDe _) = []
getIdsForPresentation (CSy s) = [symbolId s]
getIdsForPresentation (CIm _) = []
getIdsForPresentation (CAd a) = map sortDefName (adtSortDefs a)
getIdsForPresentation (CCo {}) = []

-- | Axiom
data Axiom =
  Axiom 
    {
        axiomName :: XmlId
      , axiomCMPs :: [CMP]
      , axiomFMPs :: [FMP]
    }
    deriving Show

mkAxiom::XmlId->[CMP]->[FMP]->Axiom
mkAxiom = Axiom

-- | CMP
data CMP =
  CMP
    {
      cmpContent :: MText
    }
  deriving Show

mkCMP::MText->CMP
mkCMP = CMP

-- | FMP
data FMP =
  FMP
    {
        fmpLogic :: Maybe XmlString
      , fmpContent :: Either OMObject ([Assumption],[Conclusion])
    }
  deriving Show

-- | Assumption (incomplete)
data Assumption = Assumption
  deriving Show

data Conclusion = Conclusion
  deriving Show

-- | Definition (incomplete)
data Definition =
  Definition
    {
        definitionId :: XmlId
      , definitionCMPs :: [CMP]
      , definitionFMPs :: [FMP]
    }
  deriving Show

mkDefinition::XmlId->[CMP]->[FMP]->Definition
mkDefinition = Definition

-- | ADT
data ADT =
  ADT
    {
        adtId :: Maybe XmlId
      , adtSortDefs::[SortDef]
    }
  deriving Show

data SortType = STFree | STGenerated | STLoose

mkADT::[SortDef]->ADT
mkADT = ADT Nothing

mkADTEx::Maybe XmlId->[SortDef]->ADT
mkADTEx = ADT 

instance Show SortType where
  show STFree = "free"
  show STGenerated = "generated"
  show STLoose = "loose"

instance Read SortType where
  readsPrec _ s =
    if s == "free"
      then
        [(STFree,"")]
      else
        if s == "generated"
          then
            [(STGenerated, "")]
          else
            if s == "loose"
              then
                [(STLoose, "")]
              else
                []

-- | SortDef
data SortDef =
  SortDef
    {
        sortDefName :: XmlId
      , sortDefRole :: SymbolRole
      , sortDefType :: SortType
      , sortDefConstructors :: [Constructor]
      , sortDefInsorts :: [Insort]
    }
  deriving Show

mkSortDefE::XmlId->SymbolRole->SortType->[Constructor]->[Insort]->SortDef
mkSortDefE = SortDef

mkSortDef::XmlId->[Constructor]->[Insort]->SortDef
mkSortDef xid cons ins = mkSortDefE xid SRSort STFree cons ins

-- | Constructor
data Constructor =
  Constructor
    {
        constructorName::XmlId
      , constructorRole::SymbolRole
      , constructorArguments :: [Type]
    } 
  deriving Show

mkConstructorE::XmlId->SymbolRole->[Type]->Constructor
mkConstructorE = Constructor

mkConstructor::XmlId->[Type]->Constructor
mkConstructor xid types = Constructor xid SRObject types

-- | Insort
data Insort =
  Insort
    {
      insortFor :: OMDocRef
    }
  deriving Show

mkInsort::OMDocRef->Insort
mkInsort = Insort

-- | Inclusion-Conservativity
data Conservativity = CNone | CMonomorphism | CDefinitional | CConservative
  deriving Eq

instance Show Conservativity where
  show CNone = "none"
  show CMonomorphism = "monomorphism"
  show CDefinitional = "definitional"
  show CConservative = "conservative"

instance Read Conservativity where
  readsPrec _ s =
    case s of
      "monomorphism" -> [(CMonomorphism, "")]
      "definitional" -> [(CDefinitional, "")]
      "conservative" -> [(CConservative, "")]
      "none" -> [(CNone, "")]
      _ -> []

-- | Inclusions
data Inclusion =
    TheoryInclusion
      {
          inclusionFrom :: OMDocRef
        , inclusionTo :: OMDocRef
        , inclusionMorphism :: Maybe Morphism
        , inclusionId :: Maybe XmlId
        , inclusionConservativity :: Conservativity
      }
  | AxiomInclusion
      {
          inclusionFrom :: OMDocRef
        , inclusionTo :: OMDocRef
        , inclusionMorphism :: Maybe Morphism
        , inclusionId :: Maybe XmlId
        , inclusionConservativity :: Conservativity
      }
  deriving Show

-- | OMDoc Morphism
data Morphism =
  Morphism
    {
        morphismId :: Maybe XmlId
      , morphismHiding :: [XmlId]
      , morphismBase  :: [XmlId]
      , morphismRequations :: [ ( MText, MText ) ]
    }
    deriving Show

-- Mathematical Text (incomplete)
data MText = MTextText String | MTextTerm String | MTextPhrase String | MTextOM OMObject
  deriving Show

-- OMDoc Mathematical Object
data OMDocMathObject = OMOMOBJ OMObject | OMLegacy String | OMMath String
  deriving (Show)

-- | OMOBJ
data OMObject = OMObject OMElement
  deriving (Show, Eq)

mkOMOBJ::forall e . (OMElementClass e)=>e->OMObject
mkOMOBJ e = OMObject (toElement e)

-- | OMS
data OMSymbol =
  OMS
    {
        omsCD :: XmlId
      , omsName :: XmlId
    }
    deriving (Show, Eq)

mkOMS::XmlId->XmlId->OMSymbol
mkOMS = OMS

mkOMSE::XmlId->XmlId->OMElement
mkOMSE xcd xid = toElement $ mkOMS xcd xid

-- | OMI
data OMInteger =
  OMI
    {
      omiInt :: Int
    }
    deriving (Show, Eq)

mkOMI::Int->OMInteger
mkOMI = OMI

mkOMIE::Int->OMElement
mkOMIE i = toElement $ mkOMI i

-- | A Variable can be a OMV or an OMATTR
data OMVariable = OMVS OMSimpleVariable | OMVA OMAttribution
    deriving (Show, Eq)

-- | Class to use something as a Variable
class OMVariableClass a where
  toVariable::a->OMVariable
  fromVariable::OMVariable->Maybe a

instance OMVariableClass OMVariable where
  toVariable = id
  fromVariable = Just . id

instance OMVariableClass OMSimpleVariable where
  toVariable = OMVS
  fromVariable (OMVS x) = Just x
  fromVariable _ = Nothing

mkOMVar::Either OMSimpleVariable OMAttribution->OMVariable
mkOMVar (Left oms) = OMVS oms
mkOMVar (Right omattr) = OMVA omattr

mkOMVarE::Either OMSimpleVariable OMAttribution->OMElement
mkOMVarE v = toElement $ mkOMVar v

-- | OMV
data OMSimpleVariable =
  OMV
    {
      omvName :: XmlString
    }
    deriving (Show, Eq)


mkOMSimpleVar::XmlString->OMSimpleVariable
mkOMSimpleVar = OMV

mkOMSimpleVarE::XmlString->OMElement
mkOMSimpleVarE xid = toElement $ mkOMSimpleVar xid

mkOMVSVar::XmlString->OMVariable
mkOMVSVar = OMVS . mkOMSimpleVar

mkOMVSVarE::XmlString->OMElement
mkOMVSVarE xid = toElement $ OMVS $ mkOMSimpleVar xid

-- | OMATTR
data OMAttribution =
  OMATTR
    {
        omattrATP :: OMAttributionPart
      , omattrElem :: OMElement
    }
    deriving (Show, Eq)

instance OMVariableClass OMAttribution where
  toVariable = OMVA
  fromVariable (OMVA x) = Just x
  fromVariable _ = Nothing

mkOMATTR::forall e . (OMElementClass e)=>OMAttributionPart->e->OMAttribution
mkOMATTR omatp ome = OMATTR { omattrATP = omatp , omattrElem = toElement ome }

mkOMATTRE::forall e . (OMElementClass e)=>OMAttributionPart->e->OMElement
mkOMATTRE omatp ome = toElement $ mkOMATTR omatp ome

-- | OMATP
data OMAttributionPart =
  OMATP
    {
      omatpAttribs :: [(OMSymbol, OMElement)]
    }
    deriving (Show, Eq)

mkOMATP::forall e . (OMElementClass e)=>[(OMSymbol, e)]->OMAttributionPart
mkOMATP = OMATP . map (\(s, e) -> (s, toElement e))

-- | OMBVAR
data OMBindingVariables =
  OMBVAR
    {
      ombvarVars :: [OMVariable]
    }
    deriving (Show, Eq)

mkOMBVAR::forall e . (OMVariableClass e)=>[e]->OMBindingVariables
mkOMBVAR = OMBVAR . map toVariable

{- |
  OMB is actually just a bytearray for storing data.
  [Char] representation is forced by export from Codec.Base64
-}
data OMBase64 =
  OMB
    {
      -- decoded Content
      ombContent :: [Word.Word8]
    }
    deriving (Show, Eq)

mkOMB::[Word.Word8]->OMBase64
mkOMB = OMB

mkOMBE::[Word.Word8]->OMElement
mkOMBE = toElement . mkOMB

mkOMBWords::[Word.Word8]->OMBase64
mkOMBWords = OMB

mkOMBWordsE::[Word.Word8]->OMElement
mkOMBWordsE = toElement . mkOMBWords

getOMBWords::OMBase64->[Word.Word8]
getOMBWords omb = ombContent omb

-- | OMSTR
data OMString =
  OMSTR
    {
      omstrText :: String
    }
    deriving (Show, Eq)

mkOMSTR::String->OMString
mkOMSTR = OMSTR

mkOMSTRE::String->OMElement
mkOMSTRE = toElement . mkOMSTR

-- | OMF
data OMFloat =
  OMF
    {
      omfFloat :: Float
    }
    deriving (Show, Eq)

mkOMF::Float->OMFloat
mkOMF = OMF

mkOMFE::Float->OMElement
mkOMFE = toElement . mkOMF

-- | OMA
data OMApply =
  OMA
    {
      omaElements :: [OMElement]
    }
    deriving (Show, Eq)

mkOMA::forall e . (OMElementClass e)=>[e]->OMApply
mkOMA [] = error "Empty list of elements for OMA!"
mkOMA l = OMA (map toElement l)

mkOMAE::forall e . (OMElementClass e)=>[e]->OMElement
mkOMAE = toElement . mkOMA 

-- | OME
data OMError =
  OME
    {
        omeSymbol :: OMSymbol
      , omeExtra :: [OMElement]
    }
    deriving (Show, Eq)

mkOME::forall e . (OMElementClass e)=>OMSymbol->[e]->OMError
mkOME _ [] = error "Empty list of elements for OME!"
mkOME s e = OME s (map toElement e)

mkOMEE::forall e . (OMElementClass e)=>OMSymbol->[e]->OMElement
mkOMEE s e = toElement $ mkOME s e

-- | OMR
data OMReference =
  OMR
    {
      omrHRef :: URI.URI
    }
    deriving (Show, Eq)

mkOMR::URI.URI->OMReference
mkOMR = OMR

mkOMRE::URI.URI->OMElement
mkOMRE = toElement . mkOMR

-- | OMB
data OMBind =
  OMBIND
    {
        ombindBinder :: OMElement
      , ombindVariables :: OMBindingVariables
      , ombindExpression :: OMElement
    }
    deriving (Show, Eq)

mkOMBIND::forall e1 e2 . (OMElementClass e1, OMElementClass e2)=>e1->OMBindingVariables->e2->OMBind
mkOMBIND binder bvars expr =
  OMBIND
    {
        ombindBinder = toElement binder
     , ombindVariables = bvars
      , ombindExpression = toElement expr
    }

mkOMBINDE::forall e1 e2 . (OMElementClass e1, OMElementClass e2)=>e1->OMBindingVariables->e2->OMElement
mkOMBINDE binder vars expr = toElement $ mkOMBIND binder vars expr

-- | Elements for Open Math
data OMElement =
    OMES OMSymbol
  | OMEV OMSimpleVariable
  | OMEI OMInteger
  | OMEB OMBase64
  | OMESTR OMString
  | OMEF OMFloat
  | OMEA OMApply
  | OMEBIND OMBind
  | OMEE OMError
  | OMEATTR OMAttribution
  | OMER OMReference
  | OMEC (Maybe OMElement) String
  deriving (Show, Eq)

-- | insert a comment into an open-math structure (use with caution...)
mkOMComment::String->OMElement
mkOMComment = OMEC Nothing

mkOMCommented::OMElementClass e=>String->e->OMElement
mkOMCommented cmt e = OMEC (Just (toElement e)) cmt

-- | Class of Elements for Open Math
class OMElementClass a where
  toElement::a->OMElement
  fromElement::OMElement->Maybe a

instance OMElementClass OMSymbol where
  toElement = OMES
  fromElement (OMES oms) = Just oms
  fromElement _ = Nothing

instance OMElementClass OMInteger where
  toElement = OMEI
  fromElement (OMEI x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMVariable where
  toElement (OMVS omv) = OMEV omv
  toElement (OMVA omattr) = OMEATTR omattr
  fromElement (OMEV omv) = Just (OMVS omv)
  fromElement (OMEATTR omattr) = Just (OMVA omattr)
  fromElement _ = Nothing

instance OMElementClass OMSimpleVariable where
  toElement omv = OMEV omv
  fromElement (OMEV omv) = Just omv
  fromElement _ = Nothing

instance OMElementClass OMAttribution where
  toElement = OMEATTR
  fromElement (OMEATTR x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMBase64 where
  toElement = OMEB
  fromElement (OMEB x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMString where
  toElement = OMESTR
  fromElement (OMESTR x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMFloat where
  toElement = OMEF
  fromElement (OMEF x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMApply where
  toElement = OMEA
  fromElement (OMEA x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMError where
  toElement = OMEE
  fromElement (OMEE x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMReference where
  toElement = OMER
  fromElement (OMER x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMBind where
  toElement = OMEBIND
  fromElement (OMEBIND x) = Just x
  fromElement _ = Nothing

instance OMElementClass OMElement where
  toElement = id
  fromElement = Just . id

