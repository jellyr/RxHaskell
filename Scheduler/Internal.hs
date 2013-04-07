{-# LANGUAGE GADTs #-}
{-# LANGUAGE Safe #-}

module Scheduler.Internal ( SchedulerIO(..)
                          , ScheduledAction
                          , Scheduler(..)
                          , BackgroundScheduler(..)
                          , MainScheduler(..)
                          , executeScheduledAction
                          ) where

import Control.Applicative
import Control.Concurrent
import Control.Concurrent.STM
import Control.Monad
import Control.Monad.IO.Class
import Data.Functor
import Data.IORef
import Disposable

-- | An IO computation that must be performed in a scheduler of type @s@.
data SchedulerIO s a where
    SchedulerIO :: Scheduler s => IO a -> SchedulerIO s a

instance Functor (SchedulerIO s) where
    fmap f (SchedulerIO action) = SchedulerIO $ fmap f action

instance Scheduler s => Monad (SchedulerIO s) where
    return = SchedulerIO . return
    (SchedulerIO action) >>= f =
        let unwrap (SchedulerIO action) = action
        in SchedulerIO $ do
            v <- action
            unwrap $ f v

instance Scheduler s => MonadIO (SchedulerIO s) where
    liftIO = SchedulerIO

instance Scheduler s => Applicative (SchedulerIO s) where
    pure = return
    (<*>) = ap

-- | Represents an action on a scheduler, along with a flag indicating whether it should be canceled.
data ScheduledAction s where
    ScheduledAction :: Scheduler s => IORef Bool -> SchedulerIO s () -> ScheduledAction s

-- | Creates a new scheduled action, and returns a disposable which can be used to cancel it.
newScheduledAction :: Scheduler s => SchedulerIO s () -> IO (ScheduledAction s, Disposable)
newScheduledAction action = do
    ref <- newIORef False
    d <- newDisposable $ atomicModifyIORef ref $ const (True, ())
    return (ScheduledAction ref action, d)

-- | Represents a queue of IO actions which can be executed in FIFO order.
class Scheduler s where
    -- | Schedules an action on the scheduler. Returns a disposable which can be used to cancel it.
    schedule :: s -> SchedulerIO s () -> IO Disposable

    -- | Executes all current and future actions enqueued on the given scheduler.
    schedulerMain :: s -> IO ()

-- | A scheduler which runs enqueued actions in a dedicated background thread.
newtype BackgroundScheduler = BackgroundScheduler (TQueue (ScheduledAction BackgroundScheduler))

instance Scheduler BackgroundScheduler where
    schedule s@(BackgroundScheduler q) action = do
        (sa, d) <- newScheduledAction action

        let schedule' = do
                e <- isEmptyTQueue q
                writeTQueue q sa
                return e

        e <- atomically schedule'

        -- If the queue was previously empty, spin up a thread for the scheduler.
        when e $ void $ forkIO $ schedulerMain s

        return d

    schedulerMain s@(BackgroundScheduler q) = do
        m <- atomically $ tryReadTQueue q

        -- If the queue is empty, let this thread die.
        maybe (return ()) (executeScheduledAction s) m

-- | A scheduler which runs enqueued actions on the main thread.
newtype MainScheduler = MainScheduler (TQueue (ScheduledAction MainScheduler))

instance Scheduler MainScheduler where
    schedule (MainScheduler q) action = do
        (sa, d) <- newScheduledAction action
        atomically $ writeTQueue q sa
        return d

    schedulerMain s@(MainScheduler q) = do
        sa <- atomically $ readTQueue q
        executeScheduledAction s sa

-- | Executes the given action, then re-enters 'schedulerMain'.
executeScheduledAction :: Scheduler s => s -> ScheduledAction s -> IO ()
executeScheduledAction s (ScheduledAction ref (SchedulerIO action)) = do
    d <- readIORef ref
    unless d action

    yield
    schedulerMain s
