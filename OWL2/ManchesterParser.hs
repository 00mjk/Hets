{- |
Module      :  $Header$
Copyright   :  (c) Felix Gabriel Mance
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  f.mance@jacobs-university.de
Stability   :  provisional
Portability :  portable

Contains    :  Parser from Manchester Syntax to Manchester Abstract Syntax

References  :  <http://www.w3.org/TR/2009/NOTE-owl2-manchester-syntax-20091027/>
-}

module OWL2.ManchesterParser where

import OWL2.AS
import OWL2.MS
import OWL2.Parse
import OWL2.Keywords
import OWL2.ColonKeywords

import Common.Keywords
import Common.Parsec

import Text.ParserCombinators.Parsec
import qualified Data.Map as Map

optAnnos :: CharParser st a -> CharParser st (Annotations, a)
optAnnos p = do
  as <- optionalAnnos
  a <- p
  return (as, a)

optionalAnnos :: CharParser st Annotations
optionalAnnos = option [] annotations

annotations :: CharParser st Annotations
annotations = do
   pkeyword annotationsC
   fmap (map $ \ (as, (i, v)) -> Annotation as i v)
     . sepByComma . optAnnos $ pair uriP annotationValue

descriptionAnnotatedList :: CharParser st [(Annotations, ClassExpression)]
descriptionAnnotatedList = sepByComma $ optAnnos description

annotationPropertyFrame :: CharParser st Frame
annotationPropertyFrame = do
  pkeyword annotationPropertyC
  ap <- uriP
  x <- many apBit
  return $ Frame (SimpleEntity $ Entity AnnotationProperty ap) x

apBit :: CharParser st FrameBit
apBit = do
    pkeyword subPropertyOfC
    x <- sepByComma $ optAnnos uriP
    return $ ListFrameBit (Just SubPropertyOf)
              $ AnnotationBit x
  <|> do
    dr <- domainOrRange
    x <- sepByComma $ optAnnos uriP
    return $ ListFrameBit (Just (DRRelation dr))
              $ AnnotationBit x
  <|> do
    x <- annotations
    return $ AnnFrameBit x AnnotationFrameBit

datatypeBit :: CharParser st Frame
datatypeBit = do
    pkeyword datatypeC
    duri <- datatypeUri
    as1 <- many annotations
    mp <- optionMaybe $ pkeyword equivalentToC >> pair optionalAnnos dataRange
    as2 <- many annotations
    return $ Frame (SimpleEntity $ Entity Datatype duri)
      $ map (`AnnFrameBit` AnnotationFrameBit) as1 ++ case mp of
          Nothing -> []
          Just (ans, dr) -> [AnnFrameBit ans $ DatatypeBit dr]
        ++ map (`AnnFrameBit` AnnotationFrameBit) as2

classFrame :: CharParser st Frame
classFrame = do
        pkeyword classC
        iri <- description
        plain <- many classFrameBit
        -- ignore Individuals: ... !
        optional $ pkeyword individualsC >> sepByComma individualUri
        return $ Frame (ClassEntity iri) plain

classFrameBit :: CharParser st FrameBit
classFrameBit = do
    pkeyword subClassOfC
    ds <- descriptionAnnotatedList
    return $ ListFrameBit (Just SubClass) $ ExpressionBit ds
  <|> do
    e <- equivOrDisjoint
    ds <- descriptionAnnotatedList
    return $ ListFrameBit (Just (EDRelation e)) $ ExpressionBit ds
  <|> do
    pkeyword disjointUnionOfC
    as <- optionalAnnos
    ds <- sepByComma description
    return $ AnnFrameBit as $ ClassDisjointUnion ds
  <|> do
    pkeyword hasKeyC
    as <- optionalAnnos
    o <- sepByComma objectPropertyExpr
    return $ AnnFrameBit as $ ClassHasKey o []
  <|> do
    as <- annotations
    return $ AnnFrameBit as AnnotationFrameBit

objPropExprAList :: CharParser st [(Annotations, ObjectPropertyExpression)]
objPropExprAList = sepByComma $ optAnnos objectPropertyExpr

objectFrameBit :: CharParser st FrameBit
objectFrameBit = do
    r <- domainOrRange
    ds <- descriptionAnnotatedList
    return $ ListFrameBit (Just (DRRelation r))
              $ ExpressionBit ds
  <|> do
    characterKey
    ds <- sepByComma $ optAnnos objectPropertyCharacter
    return $ ListFrameBit Nothing
              $ ObjectCharacteristics ds
  <|> do
    subPropertyKey
    ds <- objPropExprAList
    return $ ListFrameBit (Just SubPropertyOf)
              $ ObjectBit ds
  <|> do
    e <- equivOrDisjoint
    ds <- objPropExprAList
    return $ ListFrameBit (Just (EDRelation e))
            $ ObjectBit ds
  <|> do
    pkeyword inverseOfC
    ds <- objPropExprAList
    return $ ListFrameBit (Just InverseOf)
            $ ObjectBit ds
  <|> do
    pkeyword subPropertyChainC
    as <- optionalAnnos
    os <- sepBy1 objectPropertyExpr (keyword oS)
    return $ AnnFrameBit as $ ObjectSubPropertyChain os
  <|> do
    as <- annotations
    return $ AnnFrameBit as AnnotationFrameBit

objectPropertyFrame :: CharParser st Frame
objectPropertyFrame = do
  pkeyword objectPropertyC
  ouri <- objectPropertyExpr
  as <- many objectFrameBit
  return $ Frame (ObjectEntity ouri) as

dataPropExprAList :: CharParser st [(Annotations, DataPropertyExpression)]
dataPropExprAList = sepByComma $ optAnnos uriP

dataFrameBit :: CharParser st FrameBit
dataFrameBit = do
    pkeyword domainC
    ds <- descriptionAnnotatedList
    return $ ListFrameBit (Just (DRRelation ADomain)) $ ExpressionBit ds
  <|> do
    pkeyword rangeC
    ds <- sepByComma $ optAnnos dataRange
    return $ ListFrameBit Nothing $ DataPropRange ds
  <|> do
    characterKey
    as <- optionalAnnos
    keyword functionalS
    return $ AnnFrameBit as DataFunctional
  <|> do
    subPropertyKey
    ds <- dataPropExprAList
    return $ ListFrameBit (Just SubPropertyOf) $ DataBit ds
  <|> do
    e <- equivOrDisjoint
    ds <- dataPropExprAList
    return $ ListFrameBit (Just (EDRelation e)) $ DataBit ds
  <|> do
    as <- annotations
    return $ AnnFrameBit as AnnotationFrameBit

dataPropertyFrame :: CharParser st Frame
dataPropertyFrame = do
  pkeyword dataPropertyC
  duri <- uriP
  as <- many dataFrameBit
  return $ Frame (SimpleEntity $ Entity DataProperty duri) as

fact :: CharParser st Fact
fact = do
  pn <- option Positive $ keyword notS >> return Negative
  u <- uriP
  do
      c <- literal
      return $ DataPropertyFact pn u c
    <|> do
      t <- individualUri
      return $ ObjectPropertyFact pn (ObjectProp u) t

iFrameBit :: CharParser st FrameBit
iFrameBit = do
    pkeyword typesC
    ds <- descriptionAnnotatedList
    return $ ListFrameBit (Just Types) $ ExpressionBit ds
  <|> do
    s <- sameOrDifferent
    is <- sepByComma $ optAnnos individualUri
    return $ ListFrameBit (Just (SDRelation s))
          $ IndividualSameOrDifferent is
  <|> do
    pkeyword factsC
    fs <- sepByComma $ optAnnos fact
    return $ ListFrameBit Nothing $ IndividualFacts fs
  <|> do
    a <- annotations
    return $ AnnFrameBit a AnnotationFrameBit

individualFrame :: CharParser st Frame
individualFrame = do
  pkeyword individualC
  iuri <- individualUri
  as <- many iFrameBit
  return $ Frame (SimpleEntity $ Entity NamedIndividual iuri) as

misc :: CharParser st Frame
misc = do
    e <- equivOrDisjointKeyword classesC
    as <- optionalAnnos
    ds <- sepByComma description
    return $ Frame (Misc as) [ListFrameBit (Just (EDRelation e))
        $ ExpressionBit $ map (\ x -> ([], x)) ds]
  <|> do
    e <- equivOrDisjointKeyword propertiesC
    as <- optionalAnnos
    es <- sepByComma objectPropertyExpr
    -- indistinguishable from dataProperties
    return $ Frame (Misc as) [ListFrameBit (Just (EDRelation e))
        $ ObjectBit $ map (\ x -> ([], x)) es]
  <|> do
    s <- sameOrDifferentIndu
    as <- optionalAnnos
    is <- sepByComma individualUri
    return $ Frame (Misc as) [ListFrameBit (Just (SDRelation s))
        $ IndividualSameOrDifferent $ map (\ x -> ([], x)) is]

frames :: CharParser st [Frame]
frames = many $ datatypeBit <|> classFrame
  <|> objectPropertyFrame <|> dataPropertyFrame <|> individualFrame
  <|> annotationPropertyFrame <|> misc

basicSpec :: CharParser st OntologyDocument
basicSpec = do
  nss <- many nsEntry
  ou <- option dummyQName $ pkeyword ontologyC >> uriP
  ie <- many importEntry
  ans <- many annotations
  as <- frames
  return emptyOntologyDoc
    { ontology = emptyOntologyD
      { ontFrames = as
      , imports = ie
      , ann = ans
      , name = ou }
    , prefixDeclaration = Map.fromList $
      [ ("owl", "http://www.w3.org/2002/07/owl#")
      , ("rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#")
      , ("rdfs", "http://www.w3.org/2000/01/rdf-schema#")
      , ("xsd", "http://www.w3.org/2001/XMLSchema#")
      , ("", showQU dummyQName ++ "#") ]
      ++ map (\ (p, q) -> (p, showQU q)) nss }
