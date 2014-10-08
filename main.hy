
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
    (try (.get Feed (= Feed.url url))
        (except [e Exception]
            (.save (apply Feed [] {"title" title "url" url "category" category})))))

(defn opmlexport []
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
    (let [[tree (fromstring buffer)]]
        (for [f (.xpath tree "//outline")]
            (add-feed (.get f "text" "Untitled") (.get f "xmlUrl") (.get f "category" "Uncategorized")))))
            
(defn slurp-file [filename]
    (.read (open filename "rb")))


(defn fetch-feeds [feeds]
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
            (:data result)))))

(defn parse-feeds [feed-data]
   (for [data feed-data]
       (yield (.get (parse data) "entries" []))))

(defn handle-items [chunk]
  (for [items chunk]
    (for [i items]
        (try 
            (let [[guid (.get i "id" (.get i "link"))]
                  [item (.get Item (= Item.guid guid))]
                  [updated (.fromtimestamp datetime (mktime (.get i "updated_parsed" (gmtime 0))))]]
                (if (> updated item.seen)
                    (do (setv item.seen updated)
                        (.save item)
                        (print (.fields item)))))
            (except [e Exception]
                (let [[guid (.get i "id" (.get i "link"))]
                      [item (apply Item [] {"guid" guid})]]
                      (.save item)
                      (print (.fields item))))))))
        
(defn fetch-all []
  (-> (.select Feed)
      (fetch-feeds)
      (parse-feeds)
      (handle-items)))


(opmlimport (slurp-file "test.opml"))
(print (opmlexport))

;(fetch-all)
(fetch-all)
