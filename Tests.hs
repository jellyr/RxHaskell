module Tests where

import Control.Monad
import Control.Monad.Zip
import Data.Monoid
import Prelude hiding (filter, take)
import Disposable
import Event
import Scheduler
import Signal
import Signal.Operators
import Signal.Scheduled
import Subject
import Subscriber

hello = fromFoldable ["hello"]
world = fromFoldable ["world"]

testBinding =
    let ss =
            signal $ \sub -> do
                send sub $ NextEvent hello
                send sub $ NextEvent world
                send sub CompletedEvent
                return Disposable.empty
    in join ss >>: print

testSequencing = do
    (hello >> world) >>: print
    (world >> hello) >>: print

testAppending = do
    hello
        `mappend` mempty
        >>: print

    hello
        `mappend` world
        >>: print

    world
        `mappend` hello
        >>: print

testSubject = do
    (subj, s) <- newSubject
    s >>: print
    send subj $ NextEvent "hello world"

testFilter = do
    hello
        `mappend` world
        `filter` (\(x:xs) -> x == 'h')
        >>: print

testDoEvent = do
    hello
        `doEvent` (\_ -> putStrLn "event")
        >>: print

testDoNext = do
    hello
        `doNext` (\_ -> putStrLn "next")
        >>: print

testDoCompleted = do
    hello
        `doCompleted` putStrLn "completed"
        >>: print

testTake = do
    fromFoldable ["foo", "bar", "buzz", "baz"]
        `take` 2
        >>: print

testZip = do
    let zipSub (NextEvent (a, b)) = putStrLn $ a ++ " / " ++ b
        zipSub x = print x

    mzip (fromFoldable ["foo", "bar"]) (fromFoldable ["buzz", "baz"])
        >>: zipSub

testMaterialize = do
    materialize hello
        >>: print

    dematerialize (materialize hello)
        >>: print

testScheduling = do
    s <- newScheduler
    s' <- newScheduler
    mapM_ (schedule s . print) [1..50]
    mapM_ (schedule s' . print) [1..50]

testScheduledSignal = do
    s <- newScheduler
    sig <- start s $ \sub -> do
        send sub $ NextEvent "foo"
        send sub $ NextEvent "bar"
        send sub CompletedEvent
    sig >>: print
