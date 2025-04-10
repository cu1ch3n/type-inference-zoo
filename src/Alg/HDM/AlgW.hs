{-# LANGUAGE PatternSynonyms #-}

module Alg.HDM.AlgW (runAlgW) where

import Control.Monad (foldM)
import Control.Monad.Except ( MonadError(throwError) )
import Control.Monad.Writer (MonadTrans (lift), MonadWriter (tell))
import Data.List (intercalate)
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Tree (Tree (Node))
import Lib (InferMonad, freshTVar, runInferMonad)
import Syntax (TmVar, Trm (..), TyVar, Typ (..), pattern TAll)
import Unbound.Generics.LocallyNameless hiding (Subst)
import Unbound.Generics.LocallyNameless.Internal.Fold (toListOf)

type Env = Map.Map TmVar Typ

type Subst = Map.Map TyVar Typ

-- remove :: Env -> TmVar -> Env
-- remove env x = Map.delete x env

apply :: Subst -> Typ -> Typ
apply = substs . Map.toList

nullSubst :: Subst
nullSubst = Map.empty

compSubst :: Subst -> Subst -> Subst
compSubst s1 s2 = Map.map (apply s1) s2 `Map.union` s1

inst :: Typ -> InferMonad Typ
inst (TAll bnd) = unbind bnd >>= inst . snd
inst ty = return ty

gen :: Env -> Typ -> Typ
gen env ty = foldl (\ty' x -> TAll $ bind x ty') ty ftv
  where
    tFtv = Set.fromList $ toListOf fv ty
    envFtv = Set.fromList $ concatMap (toListOf fv) $ Map.elems env
    ftv = Set.toList $ tFtv `Set.difference` envFtv

mgu :: Typ -> Typ -> InferMonad (Subst, Tree String)
mgu ty1 ty2 = do
  lift $ tell ["Unifying: " ++ show ty1 ++ " ~ " ++ show ty2]
  case (ty1, ty2) of
    (TArr ty1' ty1'', TArr ty2' ty2'') -> do
      (s1, tree1) <- mgu ty1' ty2'
      (s2, tree2) <- mgu (apply s1 ty1'') (apply s1 ty2'')
      ret (s1 `compSubst` s2) [tree1, tree2]
    (TVar a, ty) -> varBind a ty >>= \s -> ret s []
    (ty, TVar a) -> varBind a ty >>= \s -> ret s []
    (TInt, TInt) -> ret nullSubst []
    (TBool, TBool) -> ret nullSubst []
    (TTuple tys, TTuple tys')
      | length tys == length tys' ->
          foldM
            ( \(s, trees) (ty, ty') -> do
                (s', tree) <- mgu (apply s ty) (apply s ty')
                return (s' `compSubst` s, trees ++ [tree])
            )
            (nullSubst, [])
            (zip tys tys')
            >>= uncurry ret
    _ -> throwError $ "cannot unify " ++ show ty1 ++ " with " ++ show ty2
  where
    showInput :: String
    showInput = show ty1 ++ " ~ " ++ show ty2

    showOutput :: Subst -> String
    showOutput s = showInput ++ " ~> " ++ showSubst s

    ret :: Subst -> [Tree String] -> InferMonad (Subst, Tree String)
    ret s trees = do
      lift $ tell ["Unified: " ++ showOutput s]
      return (s, Node ("Unify: " ++ showOutput s) trees)

varBind :: TyVar -> Typ -> InferMonad Subst
varBind a ty
  | aeq ty (TVar a) = return nullSubst
  | a `elem` toListOf fv ty = throwError $ show a ++ " occurs in " ++ show ty
  | otherwise = return $ Map.singleton a ty

algW :: Env -> Trm -> InferMonad (Subst, Typ, Tree String)
algW env tm = do
  lift $ tell ["Infering: " ++ showInput]
  case tm of
    LitInt _ -> ret "LitInt" nullSubst TInt []
    LitBool _ -> ret "LitBool" nullSubst TBool []
    Var x -> case Map.lookup x env of
      Nothing -> throwError $ "unbound variable " ++ show x
      Just poly -> do
        mono <- inst poly
        ret "Var" nullSubst mono []
    Lam bnd -> do
      (x, tm') <- unbind bnd
      a <- freshTVar
      let env' = env `Map.union` Map.singleton x (TVar a)
      (s1, ty1, tree) <- algW env' tm'
      ret "Lam" s1 (TArr (apply s1 (TVar a)) ty1) [tree]
    App tm1 tm2 -> do
      a <- freshTVar
      (s1, ty1, tree1) <- algW env tm1
      (s2, ty2, tree2) <- algW (Map.map (apply s1) env) tm2
      (s3, tree3) <- mgu (apply s2 ty1) (TArr ty2 (TVar a))
      ret "App" (s3 `compSubst` s2 `compSubst` s1) (apply s3 (TVar a)) [tree1, tree2, tree3]
    Let tm1 bnd -> do
      (x, tm2) <- unbind bnd
      (s1, ty1, tree1) <- algW env tm1
      let ty' = gen (Map.map (apply s1) env) ty1
          env' = Map.insert x ty' env
      (s2, ty2, tree2) <- algW (Map.map (apply s1) env') tm2
      ret "Let" (s2 `compSubst` s1) ty2 [tree1, tree2]
    Tuple tms -> do
      (s, tys, trees) <-
        foldM
          ( \(s', tys', trees') tm' -> do
              (s'', ty', tree') <- algW (Map.map (apply s') env) tm'
              return (s'' `compSubst` s', tys' ++ [ty'], trees' ++ [tree'])
          )
          (nullSubst, [], [])
          tms
      ret "Tuple" s (TTuple tys) trees
    _ -> throwError "not implemented"
  where
    showInput :: String
    showInput = showEnv env ++ " |- " ++ show tm

    showOutput :: Subst -> Typ -> String
    showOutput s ty = showInput ++ " : " ++ show ty ++ " with " ++ showSubst s
    ret :: String -> Subst -> Typ -> [Tree String] -> InferMonad (Subst, Typ, Tree String)
    ret rule s ty trees = do
      lift $ tell ["Infered[" ++ rule ++ "]: " ++ showOutput s ty]
      return (s, ty, Node (rule ++ ": " ++ showOutput s ty) trees)

runAlgW :: Trm -> Either String (Tree String)
runAlgW tm = case runInferMonad $ algW Map.empty tm of
  Left errs -> Left (intercalate "\n" errs)
  Right ((_, _, tree), _) -> Right tree

showEnv :: Env -> String
showEnv env = intercalate ", " $ map (\(x, ty) -> show x ++ ": " ++ show ty) (Map.toList env)

showSubst :: Subst -> String
showSubst s = "{" ++ intercalate ", " (map (\(a, ty) -> show ty ++ " / " ++ show a) (Map.toList s)) ++ "}"
