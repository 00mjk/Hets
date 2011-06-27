{- |
Module      :  $Header$
Copyright   :  (c) C. Maeder, DFKI Gmbh
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

Datatypes specific to the Functional Syntax of OWL 2

References:
  <http://www.w3.org/TR/2009/REC-owl2-syntax-20091027/#Functional-Style_Syntax>
-}

module OWL2.FS where

import Common.Id (GetRange)

import OWL2.AS

-- * AXIOMS

data Axiom = PlainAxiom [Annotation] PlainAxiom
    deriving (Show, Eq, Ord)

instance GetRange Axiom

data PlainAxiom =
    AnnotationAssertion IRI
  | AnnotationAxiom Relation AnnotationProperty IRI
  | SubClassOf SubClass SuperClass
  | EquivOrDisjointClasses EquivOrDisjoint [ClassExpression] -- min. 2 desc.
  | DisjointUnion Class [ClassExpression] -- min. 2 desc.
  | SubObjectPropertyOf SubObjectPropertyExpression ObjectPropertyExpression
  | EquivOrDisjointObjectProperties EquivOrDisjoint [ObjectPropertyExpression]
    -- min. 2  ObjectPropertyExpression
  | ObjectPropertyDomainOrRange DomainOrRange ObjectPropertyExpression
      ClassExpression
  | InverseObjectProperties ObjectPropertyExpression ObjectPropertyExpression
  | ObjectPropertyCharacter Character ObjectPropertyExpression
  | SubDataPropertyOf DataPropertyExpression DataPropertyExpression
  | EquivOrDisjointDataProperties EquivOrDisjoint [DataPropertyExpression]
    -- min. 2 DataPropertyExpressions
  | DataPropertyDomainOrRange DataDomainOrRange DataPropertyExpression
  | FunctionalDataProperty DataPropertyExpression
  | SameOrDifferentIndividual SameOrDifferent [Individual]
  | ClassAssertion ClassExpression Individual
    -- arguments are reversed from OWL-1
  | ObjectPropertyAssertion
      (Assertion ObjectPropertyExpression TargetIndividual)
  | DataPropertyAssertion (Assertion DataPropertyExpression TargetValue)
  | Declaration Entity
  | DatatypeDefinition Datatype DataRange
  | HasKey ClassExpression [ObjectPropertyExpression] [DataPropertyExpression]
    deriving (Show, Eq, Ord)

type SubClass = ClassExpression
type SuperClass = ClassExpression

data Assertion a b = Assertion a PositiveOrNegative SourceIndividual b
    deriving (Show, Eq, Ord)
