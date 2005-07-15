{- |
Module      :  $Header$
Copyright   :  (c) Heng Jiang, Uni Bremen 2004-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  jiang@tzi.de
Stability   :  provisional
Portability :  portable

Here is the place where the class Logic is instantiated for CASL.
   Also the instances for Syntax an Category.
-}

module OWL_DL.AS where

{- -- global: ShATermConvertible !-}

import Text.XML.HXT.DOM.XmlTreeTypes
import qualified Common.Lib.Map as Map
 
type URIreference =  QName
-- type URIreference = String

type DatatypeID = URIreference
type ClassID = URIreference
type IndividualID = URIreference
type OntologyID = URIreference
type DatavaluedPropertyID = URIreference
type IndividualvaluedPropertyID = URIreference
type AnnotationPropertyID = URIreference
type OntologyPropertyID = URIreference

type Namespace = Map.Map String String      -- prefix:localname
data Message = Message [(String, String, String)] deriving (Show)
type Validation = String


-- | Data structur for Ontologies
data Ontology = Ontology 
                         (Maybe OntologyID)
                         [Directive] 
--                         [Namespace]     -- NTrees XNode : namespaces
                deriving (Show, Eq)
data Directive = Anno Annotation | Ax Axiom | Fc Fact
                 deriving (Show, Eq)
data Annotation = OntoAnnotation
                         OntologyPropertyID
                         OntologyID
                | URIAnnotation 
                         AnnotationPropertyID 
                         URIreference
                | DLAnnotation 
                         AnnotationPropertyID 
                         DataLiteral
                | IndivAnnotation 
                         AnnotationPropertyID 
                         Individual
                  deriving (Show, Eq,Ord)

-- | Data literal
data DataLiteral = TypedL TypedLiteral 
                 | PlainL PlainLiteral
                 | Plain  LexicalForm
                 | RDFSL  RDFSLiteral
                   deriving (Show, Eq,Ord)

type RDFSLiteral = String

type TypedLiteral = (LexicalForm, URIreference)  
                    -- ^ consist of a lexical representatoin and a URI.                   
type PlainLiteral = (LexicalForm, LanguageTag)  
                    -- ^ Unicode string in Normal Form C and an optional language tag
type LexicalForm = String        
type LanguageTag = String

-- | Data structur for facts
data Fact = Indiv Individual 
          | SameIndividual 
                  IndividualID 
                  IndividualID 
                  [IndividualID]
          | DifferentIndividuals 
                  IndividualID 
                  IndividualID 
                  [IndividualID]
            deriving (Show, Eq,Ord)

data Individual = Individual (Maybe IndividualID) [Annotation] [Type] [Value]
                  deriving (Show, Eq,Ord)
data Value = ValueID    IndividualvaluedPropertyID IndividualID
           | ValueIndiv IndividualvaluedPropertyID Individual
           | ValueDL    DatavaluedPropertyID DataLiteral
             deriving (Show, Eq,Ord)
type Type = Description

-- | Axiom (Class Axioms, Descriptions, Restrictions, Property Axioms)
data Axiom = Thing
           | OWL_DL.AS.Nothing
           | Class 
                   ClassID 
                   Bool -- ^ True == deprecated
                   Modality 
                   [Annotation] 
                   [Description]
           | EnumeratedClass 
                   ClassID 
                   Bool -- ^ True == deprecated
                   [Annotation] 
                   [IndividualID]
           | DisjointClasses 
                   Description 
                   Description 
                   [Description]
           | EquivalentClasses 
                   Description 
                   [Description]
           | SubClassOf 
                   Description 
                   Description
           | Datatype 
                   DatatypeID 
                   Bool -- ^ True == deprecated  
                   [Annotation]
           | DatatypeProperty 
                   DatavaluedPropertyID 
                   Bool -- ^ True == deprecated  
                   [Annotation] 
                   [DatavaluedPropertyID]  -- ^ super properties 
                   Bool -- ^ True == Functional  
                   [Description] -- ^ Domain 
                   [DataRange] -- ^ Range
           | ObjectProperty IndividualvaluedPropertyID 
                   Bool -- ^ True == deprecated 
                   [Annotation] 
                   [IndividualvaluedPropertyID] -- ^ super properties 
                   (Maybe IndividualvaluedPropertyID)
                      -- ^ inverse of property 
                   Bool -- ^ True == symmetric
                   (Maybe Func) 
                   [Description] -- ^ Domain 
                   [Description] -- ^ Range             
           | AnnotationProperty 
                   -- ^ Declaration of a new annotation property
                   AnnotationPropertyID 
                   [Annotation]
           | OntologyProperty 
                   -- ^ Declaration of a new ontology property
                   OntologyPropertyID 
                   [Annotation]
           | DEquivalentProperties 
                   DatavaluedPropertyID 
                   DatavaluedPropertyID 
                   [DatavaluedPropertyID]
           | DSubPropertyOf 
                   DatavaluedPropertyID 
                   DatavaluedPropertyID
           | IEquivalentProperties
                   IndividualvaluedPropertyID 
                   IndividualvaluedPropertyID 
                   [IndividualvaluedPropertyID]
           | ISubPropertyOf 
                   IndividualvaluedPropertyID 
                   IndividualvaluedPropertyID
             deriving (Show,Eq,Ord)

data Func = Functional | InverseFunctional | Functional_InverseFunctional | Transitive
            deriving (Show, Eq,Ord)

data Modality = Complete | Partial
                deriving (Show, Eq,Ord)

data Description = DC ClassID 
                 | DR Restriction
                 | UnionOf [Description]
                 | IntersectionOf [Description]
                 | ComplementOf Description
                 | OneOfDes [IndividualID]
                   deriving (Show,Eq,Ord)

data Restriction = DataRestriction DatavaluedPropertyID Drcomponent [Drcomponent]
                 | IndivRestriction IndividualvaluedPropertyID Ircomponent [Ircomponent]
                   deriving (Show, Eq,Ord)

data Drcomponent = DRCAllValuesFrom DataRange
                 | DRCSomeValuesFrom DataRange
                 | DRCValue DataLiteral
                 | DRCCardinality Cardinality
                   deriving (Show, Eq,Ord)
                   
data Ircomponent = IRCAllValuesFrom Description
                 | IRCSomeValuesFrom Description
                 | IRCValue IndividualID
                 | IRCCardinality Cardinality
                   deriving (Show, Eq,Ord)

data Cardinality = MinCardinality Int
                 | MaxCardinality Int
                 | Cardinality Int
                   deriving (Show, Eq,Ord)

data DataRange = DID DatatypeID 
               | OneOfData [DataLiteral]
               | RLit RDFSLiteral       -- ^ rdfs:literal
                 deriving (Show, Eq,Ord)

