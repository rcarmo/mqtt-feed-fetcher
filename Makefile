DATABASE=/tmp/feeds.db

repl:
	hy

deps:
	pip install -r requirements.txt

init:
	FEED_DATABASE=$(DATABASE) python db.py

clean:
	rm $(DATABASE)

fetch:
	FEED_DATABASE=$(DATABASE) MQTT_BROKER=localhost MQTT_TOPIC=rss/new hy main.hy
