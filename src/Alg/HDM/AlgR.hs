{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternSynonyms #-}

module Alg.HDM.AlgR (runAlgR) where

import Control.Monad.Except (MonadError (throwError))
import Control.Monad.Writer (MonadTrans (lift), MonadWriter (tell))
import Data.Bifunctor (bimap)
import Data.Foldable (find)
import Data.List (intercalate)
import Data.Tree (Tree (Node))
import Lib (InferMonad, freshTVar, runInferMonad)
import Syntax (TmVar, Trm (..), TyVar, Typ (..), pattern TAll)
import Unbound.Generics.LocallyNameless

type ExCtx = [TyVar]

data TyCtxEntry = TVarBnd TyVar | ExCtx ExCtx | VarBnd TmVar Typ | Invis ExCtx Typ

type TyCtx = [TyCtxEntry]

type TyEqs = [(Typ, Typ)]

showExCtx :: ExCtx -> String
showExCtx = intercalate ", " . map (\a -> "^" ++ show a) . reverse

showExCtxTyp :: ExCtx -> Typ -> String
showExCtxTyp exCtx ty = "[" ++ showExCtx exCtx ++ "]" ++ show ty

showTyEqs :: TyEqs -> String
showTyEqs = intercalate ", " . map (\(ty1, ty2) -> show ty1 ++ " ~ " ++ show ty2)

instance Show TyCtxEntry where
  show (TVarBnd a) = show a
  show (ExCtx exCtx) = "(" ++ showExCtx exCtx ++ ")"
  show (VarBnd x ty) = show x ++ " : " ++ show ty
  show (Invis exCtx ty) = "{" ++ showExCtxTyp exCtx ty ++ "}"

instance {-# OVERLAPPING #-} Show TyCtx where
  show = intercalate "; " . map show . reverse

mono :: Typ -> Bool
mono (TVar _) = True
mono (ETVar _) = True
mono TInt = True
mono TBool = True
mono (TArr ty1 ty2) = mono ty1 && mono ty2
mono ty = error $ "mono: not implemented for " ++ show ty

inst :: TyCtx -> Typ -> InferMonad (ExCtx, Typ, Tree String)
inst tyCtx ty = do
  lift $ tell ["Instantiating: " ++ showInput]
  case ty of
    (TAll bnd) -> do
      (a, ty') <- unbind bnd
      (exCtx, ty'', tree) <- inst (ExCtx [a] : tyCtx) (subst a (ETVar a) ty')
      ret "InstPoly" (a : exCtx) ty'' [tree]
    _ | mono ty -> ret "InstMono" [] ty []
    _ -> throwError $ "No rule matching: " ++ showInput
  where
    showInput = show tyCtx ++ " |- " ++ show ty
    showOutput exCtx' ty' = showInput ++ " >= " ++ showExCtxTyp exCtx' ty'

    ret :: String -> ExCtx -> Typ -> [Tree String] -> InferMonad (ExCtx, Typ, Tree String)
    ret rule exCtx' ty' trees = do
      lift $ tell ["Instantiated[" ++ rule ++ "]: " ++ showOutput exCtx' ty']
      return (exCtx', ty', Node (rule ++ ": " ++ showOutput exCtx' ty') trees)

gen :: TyCtx -> Trm -> InferMonad (Typ, TyCtx, Tree String)
gen tyCtx tm = do
  lift $ tell ["Generalizing: " ++ showInput]
  (exCtx, ty, tyCtx', tree) <- infer tyCtx tm
  let ty' = foldl (\ty'' a -> TAll $ bind a (subst a (TVar a) ty'')) ty exCtx
  lift $ tell ["Generalized: " ++ showOutput ty' tyCtx']
  return (ty', tyCtx', Node ("Gen: " ++ showOutput ty' tyCtx') [tree])
  where
    showInput = show tyCtx ++ " |- " ++ show tm
    showOutput ty' tyCtx' = showInput ++ " : " ++ show ty' ++ " -| " ++ show tyCtx'

infer :: TyCtx -> Trm -> InferMonad (ExCtx, Typ, TyCtx, Tree String)
-- Note here the return Typ is actually mono
infer tyCtx tm = do
  lift $ tell ["Inferring: " ++ showInput]
  case tm of
    Var x | Just (VarBnd _ ty) <- find (\case VarBnd x' _ -> x == x'; _ -> False) tyCtx -> do
      (exCtx, ty', tree) <- inst tyCtx ty
      ret "Var" exCtx ty' tyCtx [tree]
    LitInt _ -> ret "Int" [] TInt tyCtx []
    LitBool _ -> ret "Bool" [] TBool tyCtx []
    Lam bnd -> do
      (x, e) <- unbind bnd
      a <- freshTVar
      (exCtx2, ty2, tyCtx', tree) <- infer (VarBnd x (ETVar a) : ExCtx [a] : tyCtx) e
      case tyCtx' of
        VarBnd x' ty1 : ExCtx exCtx1 : tyCtx''
          | x == x' ->
              ret "Abs" (exCtx2 ++ exCtx1) (TArr ty1 ty2) tyCtx'' [tree]
        _ -> throwError $ show tyCtx' ++ " is not of the right form"
    App tm1 tm2 -> do
      (exCtx1, ty, tyCtx1, tree1) <- infer tyCtx tm1
      (exCtx2, ty1, tyCtx2, tree2) <- infer (Invis exCtx1 ty : tyCtx1) tm2
      case tyCtx2 of
        Invis exCtx1' ty' : tyCtx2' -> do
          a <- freshTVar
          (tyCtx', tree3) <-
            unify
              (Invis [] (ETVar a) : ExCtx (a : exCtx2 ++ exCtx1') : tyCtx2')
              [(ty', TArr ty1 (ETVar a))]
          case tyCtx' of
            Invis [] ty'' : ExCtx exCtx : tyCtx'' ->
              ret "App" exCtx ty'' tyCtx'' [tree1, tree2, tree3]
            _ -> throwError $ show tyCtx' ++ " is not of the right form"
        _ -> throwError $ show tyCtx2 ++ " is not of the right form"
    Let tm1 bnd -> do
      (x, tm2) <- unbind bnd
      (ty, tyCtx', tree1) <- gen tyCtx tm1
      (exCtx, ty', tyCtx'', tree2) <- infer (VarBnd x ty : tyCtx') tm2
      case tyCtx'' of
        VarBnd x' _ : tyCtx''' | x == x' -> do
          ret "Let" exCtx ty' tyCtx''' [tree1, tree2]
        _ -> throwError $ show tyCtx'' ++ " is not of the right form"
    _ -> throwError $ "No rule matching: " ++ showInput
  where
    showInput = show tyCtx ++ " |- " ++ show tm
    showOutput exCtx ty tyCtx' = showInput ++ " : " ++ showExCtxTyp exCtx ty ++ " -| " ++ show tyCtx'

    ret :: String -> ExCtx -> Typ -> TyCtx -> [Tree String] -> InferMonad (ExCtx, Typ, TyCtx, Tree String)
    ret rule exCtx ty tyCtx' trees = do
      lift $ tell ["Inferred[" ++ rule ++ "]: " ++ showOutput exCtx ty tyCtx']
      return (exCtx, ty, tyCtx', Node (rule ++ ": " ++ showOutput exCtx ty tyCtx') trees)

unify :: TyCtx -> TyEqs -> InferMonad (TyCtx, Tree String)
unify tyCtx tyEqs = do
  lift $ tell ["Unifying: " ++ showInput]
  case tyEqs of
    [] -> ret "SolNil" tyCtx []
    _ -> do
      (tyCtx', tyEqs'') <- unifySingleStep tyCtx tyEqs
      (tyCtx'', tree) <- unify tyCtx' tyEqs''
      ret "SolCons" tyCtx'' [tree]
  where
    showInput = show tyCtx ++ " |- " ++ showTyEqs tyEqs
    showOutput tyCtx' = showInput ++ " -| " ++ show tyCtx'

    ret :: String -> TyCtx -> [Tree String] -> InferMonad (TyCtx, Tree String)
    ret rule tyCtx' trees = do
      lift $ tell ["Unified[" ++ rule ++ "]: " ++ showOutput tyCtx']
      return (tyCtx', Node (rule ++ ": " ++ showOutput tyCtx') trees)

substExCtx :: TyVar -> [TyVar] -> ExCtx -> Maybe ExCtx
substExCtx _ _ [] = Nothing
substExCtx a exVars (a' : exCtx)
  | a == a' = Just $ exVars ++ exCtx
  | otherwise = do
      exCtx' <- substExCtx a exVars exCtx
      return $ a' : exCtx'

substTyCtx :: TyVar -> Typ -> [TyVar] -> TyCtx -> InferMonad TyCtx
substTyCtx a ty exVars tyCtx = case tyCtx of
  [] -> throwError $ show a ++ " is not found"
  TVarBnd a' : tyCtx' -> do
    tyCtx'' <- substTyCtx a ty exVars tyCtx'
    return $ TVarBnd a' : tyCtx''
  ExCtx exCtx : tyCtx' ->
    case substExCtx a exVars exCtx of
      Just exCtx' ->
        return $ ExCtx exCtx' : tyCtx'
      Nothing -> do
        tyCtx'' <- substTyCtx a ty exVars tyCtx'
        return $ ExCtx exCtx : tyCtx''
  VarBnd x ty' : tyCtx' -> do
    tyCtx'' <- substTyCtx a ty exVars tyCtx'
    return $ VarBnd x (subst a ty ty') : tyCtx''
  Invis exCtx ty' : tyCtx' -> do
    case substExCtx a exVars exCtx of
      Just exCtx' ->
        return $ Invis exCtx' (subst a ty ty') : tyCtx'
      Nothing -> do
        tyCtx'' <- substTyCtx a ty exVars tyCtx'
        return $ Invis exCtx (subst a ty ty') : tyCtx''

substTyEqs :: TyVar -> Typ -> TyEqs -> TyEqs
substTyEqs a ty = map (bimap (subst a ty) (subst a ty))

before :: TyCtx -> TyVar -> TyVar -> Bool
before tyCtx a b =
  let (tyCtx1, _) = break (\case TVarBnd a' -> a == a'; _ -> False) tyCtx
      (tyCtx1', _) = break (\case TVarBnd b' -> b == b'; _ -> False) tyCtx
   in length tyCtx1 > length tyCtx1'

unifySingleStep :: TyCtx -> TyEqs -> InferMonad (TyCtx, TyEqs)
unifySingleStep tyCtx tyEqs = case tyEqs of
  (ty1, ty2) : tyEqs' -> do
    lift $ tell ["UnifyingSingleStep: " ++ showInput]
    case (ty1, ty2) of
      (TInt, TInt) -> return (tyCtx, tyEqs')
      (TBool, TBool) -> return (tyCtx, tyEqs')
      (ETVar a, ETVar b) | a == b -> return (tyCtx, tyEqs')
      (TArr ty1' ty2', TArr ty1'' ty2'') -> return (tyCtx, (ty1', ty1'') : (ty2', ty2'') : tyEqs')
      (ETVar a, TArr _ _) -> do
        a1 <- freshTVar
        a2 <- freshTVar
        tyCtx' <- substTyCtx a (TArr (ETVar a1) (ETVar a2)) [a1, a2] tyCtx
        return (tyCtx', substTyEqs a (TArr (ETVar a1) (ETVar a2)) tyEqs')
      (TArr _ _, ETVar a) -> do
        a1 <- freshTVar
        a2 <- freshTVar
        tyCtx' <- substTyCtx a (TArr (ETVar a1) (ETVar a2)) [a1, a2] tyCtx
        return (tyCtx', substTyEqs a (TArr (ETVar a1) (ETVar a2)) tyEqs')
      (ETVar a, ETVar b) | before tyCtx a b -> do
        tyCtx' <- substTyCtx b (ETVar a) [] tyCtx
        return (tyCtx', substTyEqs b (ETVar a) tyEqs')
      (ETVar b, ETVar a) | before tyCtx a b -> do
        tyCtx' <- substTyCtx b (ETVar a) [] tyCtx
        return (tyCtx', substTyEqs b (ETVar a) tyEqs')
      (ETVar a, TInt) -> do
        tyCtx' <- substTyCtx a TInt [] tyCtx
        return (tyCtx', substTyEqs a TInt tyEqs')
      (TInt, ETVar a) -> do
        tyCtx' <- substTyCtx a TInt [] tyCtx
        return (tyCtx', substTyEqs a TInt tyEqs')
      (ETVar a, TBool) -> do
        tyCtx' <- substTyCtx a TBool [] tyCtx
        return (tyCtx', substTyEqs a TBool tyEqs')
      (TBool, ETVar a) -> do
        tyCtx' <- substTyCtx a TBool [] tyCtx
        return (tyCtx', substTyEqs a TBool tyEqs')
      _ -> throwError $ "No rule matching: " ++ showInput
  [] -> throwError "Impossible"
  where
    showInput = show tyCtx ++ " |- " ++ showTyEqs tyEqs

runAlgR :: Trm -> Either String (Tree String)
runAlgR tm = case runInferMonad $ infer [] tm of
  Left err -> Left $ intercalate "\n" err
  Right ((_, _, _, tree), _) -> Right tree
