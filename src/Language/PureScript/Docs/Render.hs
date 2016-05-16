-- |
-- Functions for creating `RenderedCode` values from data types in
-- Language.PureScript.Docs.Types.
--
-- These functions are the ones that are used in markdown/html documentation
-- generation, but the intention is that you are able to supply your own
-- instead if necessary. For example, the Hoogle input file generator
-- substitutes some of these

module Language.PureScript.Docs.Render where

import Prelude.Compat

import Data.Maybe (maybeToList)
import Data.Monoid ((<>))

import Language.PureScript.Docs.RenderedCode
import Language.PureScript.Docs.Types
import Language.PureScript.Docs.Utils.MonoidExtras
import qualified Language.PureScript as P

renderDeclaration :: Declaration -> RenderedCode
renderDeclaration = renderDeclarationWithOptions defaultRenderTypeOptions

renderDeclarationWithOptions :: RenderTypeOptions -> Declaration -> RenderedCode
renderDeclarationWithOptions opts Declaration{..} =
  mintersperse sp $ case declInfo of
    ValueDeclaration ty ->
      [ ident declTitle
      , syntax "::"
      , renderType' ty
      ]
    DataDeclaration dtype args ->
      [ keyword (P.showDataDeclType dtype)
      , renderType' (typeApp declTitle args)
      ]
    ExternDataDeclaration kind' ->
      [ keywordData
      , renderType' (P.TypeConstructor (notQualified declTitle))
      , syntax "::"
      , renderKind kind'
      ]
    TypeSynonymDeclaration args ty ->
      [ keywordType
      , renderType' (typeApp declTitle args)
      , syntax "="
      , renderType' ty
      ]
    TypeClassDeclaration args implies ->
      [ keywordClass ]
      ++ maybeToList superclasses
      ++ [renderType' (typeApp declTitle args)]
      ++ [keywordWhere | any isTypeClassMember declChildren]

      where
      superclasses
        | null implies = Nothing
        | otherwise = Just $
            syntax "("
            <> mintersperse (syntax "," <> sp) (map renderConstraint implies)
            <> syntax ")" <> sp <> syntax "<="

    AliasDeclaration (P.Fixity associativity precedence) for@(P.Qualified _ alias) ->
      [ keywordFixity associativity
      , syntax $ show precedence
      , ident $ renderQualAlias for
      , keyword "as"
      , ident $ adjustAliasName alias declTitle
      ]

  where
  renderType' :: P.Type -> RenderedCode
  renderType' = renderTypeWithOptions opts

  renderQualAlias :: FixityAlias -> String
  renderQualAlias (P.Qualified mn alias)
    | mn == currentModule opts = renderAlias id alias
    | otherwise = renderAlias (\f -> P.showQualified f . P.Qualified mn) alias

  renderAlias
    :: (forall a. (a -> String) -> a -> String)
    -> Either (P.ProperName 'P.TypeName) (Either P.Ident (P.ProperName 'P.ConstructorName))
    -> String
  renderAlias f
    = either (("type " ++) . f P.runProperName)
    $ either (f P.runIdent) (f P.runProperName)

  -- adjustAliasName (P.AliasType{}) title = drop 6 (init title)
  adjustAliasName _ title = tail (init title)

renderChildDeclaration :: ChildDeclaration -> RenderedCode
renderChildDeclaration = renderChildDeclarationWithOptions defaultRenderTypeOptions

renderChildDeclarationWithOptions :: RenderTypeOptions -> ChildDeclaration -> RenderedCode
renderChildDeclarationWithOptions opts ChildDeclaration{..} =
  mintersperse sp $ case cdeclInfo of
    ChildInstance constraints ty ->
      maybeToList (renderConstraints constraints) ++ [ renderType' ty ]
    ChildDataConstructor args ->
      [ renderType' typeApp' ]
      where
      typeApp' = foldl P.TypeApp ctor' args
      ctor' = P.TypeConstructor (notQualified cdeclTitle)

    ChildTypeClassMember ty ->
      [ ident cdeclTitle
      , syntax "::"
      , renderType' ty
      ]
  where
  renderType' = renderTypeWithOptions opts

renderConstraint :: (P.Qualified (P.ProperName 'P.ClassName), [P.Type]) -> RenderedCode
renderConstraint = renderConstraintWithOptions defaultRenderTypeOptions

renderConstraintWithOptions
  :: RenderTypeOptions
  -> (P.Qualified (P.ProperName 'P.ClassName), [P.Type])
  -> RenderedCode
renderConstraintWithOptions opts (con, args) =
  renderTypeWithOptions opts (foldl P.TypeApp (P.TypeConstructor (fmap P.coerceProperName con)) args)

renderConstraints
  :: [(P.Qualified (P.ProperName 'P.ClassName), [P.Type])]
  -> Maybe RenderedCode
renderConstraints = renderConstraintsWithOptions defaultRenderTypeOptions

renderConstraintsWithOptions
  :: RenderTypeOptions
  -> [(P.Qualified (P.ProperName 'P.ClassName), [P.Type])]
  -> Maybe RenderedCode
renderConstraintsWithOptions opts constraints
  | null constraints = Nothing
  | otherwise = Just $
        syntax "("
        <> renderedConstraints
        <> syntax ")" <> sp <> syntax "=>"
  where
  renderedConstraints =
    mintersperse (syntax "," <> sp)
                 (map (renderConstraintWithOptions opts) constraints)

notQualified :: String -> P.Qualified (P.ProperName a)
notQualified = P.Qualified Nothing . P.ProperName

typeApp :: String -> [(String, Maybe P.Kind)] -> P.Type
typeApp title typeArgs =
  foldl P.TypeApp
        (P.TypeConstructor (notQualified title))
        (map toTypeVar typeArgs)

toTypeVar :: (String, Maybe P.Kind) -> P.Type
toTypeVar (s, Nothing) = P.TypeVar s
toTypeVar (s, Just k) = P.KindedType (P.TypeVar s) k
