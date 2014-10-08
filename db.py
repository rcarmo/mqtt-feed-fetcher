#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Copyright (c) 2013, Rui Carmo
Description: Database models
License: MIT (see LICENSE.md for details)
"""

import os, sys, logging, datetime

log = logging.getLogger()

from peewee import *

db = SqliteDatabase(os.environ["FEED_DATABASE"], threadlocals=True)

class CustomModel(Model):
    """Binds the database to all our models"""

    def fields(self, fields=None, exclude=None):
        model_class = type(self)
        data = {}

        fields = fields or {}
        exclude = exclude or {}
        curr_exclude = exclude.get(model_class, [])
        curr_fields = fields.get(model_class, self._meta.get_field_names())

        for field_name in curr_fields:
            if field_name in curr_exclude:
                continue
            field_obj = model_class._meta.fields[field_name]
            field_data = self._data.get(field_name)
            if isinstance(field_obj, ForeignKeyField) and field_data and field_obj.rel_model in fields:
                rel_obj = getattr(self, field_name)
                data[field_name] = rel_obj.fields(fields, exclude)
            else:
                data[field_name] = field_data
        return data

    # remember that Peewee models have an implicit integer id as primary key
    class Meta:
        database = db


class Feed(CustomModel):
    """RSS Feed"""
    enabled              = BooleanField(default=True)
    category             = CharField(default='Uncategorized', null=True)
    title                = CharField(default='Untitled', null=True)
    url                  = CharField()
    ttl                  = IntegerField(null=True,default=3600) # seconds
    etag                 = CharField(null=True)
    last_modified        = DateTimeField(null=True, default=None)
    last_status          = IntegerField(null=True) # last HTTP code
    error_count          = IntegerField(default=0)

    class Meta:
        indexes = (
            (('url',), True),
            (('last_modified',), False),
        )
        order_by = ('-last_modified',)


class Item(CustomModel):
    """Individual feed items"""
    guid    = CharField()
    seen    = DateTimeField(default=datetime.datetime.now)

    class Meta:
        indexes = (
            (('seen',), False),
            (('guid',), True),
        )
        order_by = ('-seen',)


def setup(skip_if_existing = True):
    """Create tables for all models"""
    models = [Feed, Item]

    for item in models:
        item.create_table(skip_if_existing)
    # set Write Ahead Log mode for SQLite
    db.execute_sql('PRAGMA journal_mode=WAL')
    
    
if __name__ == '__main__':
    setup()
