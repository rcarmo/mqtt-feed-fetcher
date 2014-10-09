#!/bin/env hy
(import
    [paho.mqtt.client [Client :as mqtt]]
    [time [mktime gmtime]]
    [datetime [datetime]]
    [goless [go chan select]]
    [speedparser [parse]]
    [lxml.etree [Element tostring fromstring]]
    [db [Feed Item setup]]
    [utils [fetch-url]])
    

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
            (let [[result (apply fetch-url [feed.url] {"etag" feed.etag "last_modified" feed.last-modified})]]
                (setv feed.code (:code result))
                (if (in "last-modified" (:headers result))
                    (setv feed.last-modified (.strptime datetime (get (:headers result) "last-modified") "%a, %d %b %Y %H:%M:%S %Z")))
                (if (in "etag" (:headers result))
                    (setv feed.etag (get (:headers result) "etag")))
                (setv feed.last-status (:code result))
                (print (:code result) (len (:data result)) feed.url)
                (.save feed)
                (if (= (:code result) 200)
                    (:data result)
                    nil)))))


(defn parse-feeds [feed-data]
   ; feed parser and item generator
   ; TODO - update feed TTL and other data
   (for [data feed-data]
       (yield
            (let [[feed (parse data)]]
                (map
                    ; enrich items with feed data
                    (fn [entry]
                        (for [field ["link" "author" "title" "description"]]
                            (let [[new-key (+ "feed-" field)]]
                                (assoc entry new-key (.get (.get feed "feed") field nil))))
                        entry)
                    (.get feed "entries" []))))))


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

(fetch-all)
