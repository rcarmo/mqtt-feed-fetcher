#!/bin/env hy
(import
    [paho.mqtt.client [Client :as mqtt]]
    [time [mktime gmtime]]
    [datetime [datetime]]
    [goless [go chan select]]
    [speedparser [parse]]
    [lxml.etree [Element tostring fromstring]]
    [db [Feed Item setup]]
    [utils [fetch-url slurp-file]])
    

(defn add-feed [title url category]
    ; save a feed to the database
    (try (.get Feed (= Feed.url url))
        (except [e Exception]
            (.save (apply Feed [] {"title" title "url" url "category" category})))))


(defn opmlexport []
    ; dump the whole database as OPML
    (let [[tree  (apply Element ["opml"] {"version" "1.0"})]
          [head  (Element "head")]
          [title (Element "title")]
          [body  (Element "body")]]
        (setv title.text "Exported Feeds")
        (.append head title)
        (.append tree head)
        (for [f (.select Feed)]
            (.append body (apply Element ["outline"] {"type" "rss" "text" f.title "xmlUrl" f.url "category" f.category})))
        (.append tree body)
        (apply tostring [tree] {"encoding" "UTF-8" "xml_declaration" true "pretty_print" True})))


(defn opmlimport [buffer]
    ; the nicest OPML import I ever wrote
    (let [[tree (fromstring buffer)]]
        (for [f (.xpath tree "//outline")]
            (add-feed (.get f "text" "Untitled") (.get f "xmlUrl") (.get f "category" "Uncategorized")))))
            

(defn fetch-feeds [feeds]
    ; feed data generator
    ; TODO - use feed TTL
    (for [feed feeds]
        (yield
            (let [[result  (apply fetch-url [(. feed url)] 
                                {"etag" (. feed etag) "last_modified" (. feed last-modified)})]
                  [headers (:headers result)]
                  [code    (:code result)]
                  [data    (:data result)]]
                (if (< code 300)
                    (setv (. feed last-modified) (.now datetime)))
                    (if (in "last-modified" headers)
                    (setv (. feed last-modified) (.strptime datetime (get headers "last-modified") "%a, %d %b %Y %H:%M:%S %Z")))
                (if (in "etag" headers)
                    (setv (. feed etag) (get headers "etag")))
                (setv (. feed last-status) code)
                (print code (len data) (. feed url))
                (.save feed)
                (if (>= code 400)
                    (setv (. feed error-count) (+ 1 (. feed error-count))))
                (if (= code 200)
                    {:feed feed :data data}
                    {:feed feed :data nil})))))


(defn parse-feeds [feed-seq]
   ; feed parser and item generator
   ; TODO - update feed TTL and other data
   (for [item feed-seq]
       (yield
            (let [[parsed   (parse (:data item))]
                  [feed     (:feed item)]
                  [metadata (.get parsed "feed" nil)]]
                  (if (in "title" metadata)
                    (do                    
                        (setv (. feed title) (get metadata "title"))
                        (.save feed)))
                (map
                    ; enrich items with feed data
                    (fn [entry]
                        (for [field ["link" "author" "title" "description"]]
                            (let [[new-key (+ "feed-" field)]]
                                (assoc entry new-key (.get (.get parsed "feed") field nil))))
                        entry)
                    (.get parsed "entries" []))))))


(defn handle-items [chunk]
    ; handle chunks of items and mark them as seen
    ; TODO: sliding window to "forget" older items and vacuum the database
    (for [items chunk]
        (for [i items]
            (try 
                (let [[guid (.get i "id" (.get i "link"))]
                     [item (.get Item (= Item.guid guid))]
                     [updated (.fromtimestamp datetime (mktime (.get i "updated_parsed" (gmtime 0))))]]
                    (if (> updated item.seen)
                        (do (setv item.seen updated)
                            (.save item)
                            (publish i))))
                (except [e Exception]
                    (let [[guid (.get i "id" (.get i "link"))]
                        [item (apply Item [] {"guid" guid})]]
                        (.save item)
                        (publish i)))))))


; TODO - serialization, broker connection error handling, etc.
(defn publish [item]
    (print item))


(defn fetch-all []
  (-> (.select Feed)
      (fetch-feeds)
      (parse-feeds)
      (handle-items)))


;(opmlimport (slurp-file "test.opml"))
;(print (opmlexport))

(defmain [args]
    (fetch-all))
    