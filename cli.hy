(import 
    [cmd [Cmd]]
    [db [Feed]])

(defclass FeedManager [Cmd]
    [[do-list 
        (fn [self arg]
            "list feed information"
            (for [f (.select Feed)]
                (print (. f id) (. f last-status) (. f title) (. f category) (. f last-modified ))))]])
        
(defmain [args]
    (.cmdloop (FeedManager)))