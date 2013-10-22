// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * A resource workspace implementation.
 */
library spark.workspace;

import 'dart:async';

import 'package:chrome_gen/chrome_app.dart' as chrome_gen;

import 'preferences.dart';

/**
 * The Workspace is a top-level entity that can contain files and projects. The
 * files that it contains are loose files; they do not have parent folders.
 */
class Workspace implements Container {
  Container _parent = null;
  chrome_gen.Entry _entry = null;

  List<Resource> _children = [];
  PreferenceStore _store;

  StreamController<ResourceChangeEvent> _streamController =
      new StreamController.broadcast();

  Workspace(PreferenceStore preferenceStore) {
    this._store = preferenceStore;
  }

  String get name => null;

  Container get parent => null;

  Workspace initialize() {
    // TODO: initialize workspace with saved info from previous session
  }

  Future<Resource> link(chrome_gen.Entry entity) {

    if (entity.isFile) {
      var resource = new File(this, entity);
      _children.add(resource);
      _streamController.add(new ResourceChangeEvent(resource, ResourceEventType.ADD));
      return new Future.value(resource);
    } else {
      var project = new Project(this, entity);
      _children.add(project);
      _streamController.add(new ResourceChangeEvent(project, ResourceEventType.ADD));
      return _gatherChildren(project);
    }
  }

  void unlink(Resource resource) {
    // TODO: remove resource from list of children
  }

  List<Resource> getChildren() {
   return _children;
  }

  List<File> getFiles() {
    List list = [];
    for (var child in _children) {
      if (child is File) list.add(child);
    }
    return list;
  }

  List<Project> getProjects() {
    List list = [];
    for (var child in _children) {
      if (child is Project) list.add(child);
    }
    return list;
  }

  Stream<ResourceChangeEvent> get onResourceChange => _streamController.stream;

  Project get project => null;

  void save() {
    // TODO: save workspace information - maybe in preferences?
  }

  Future<Resource> _gatherChildren(Container container) {
    chrome_gen.DirectoryEntry dir = container._entry;
    List futures = [];

    return dir.createReader().readEntries().then((entries) {
      for (chrome_gen.Entry ent in entries) {
        if (ent.isFile) {
          var file = new File(container, ent);
          container._children.add(file);
        } else {
          var folder = new Folder(container, ent);
          container._children.add(folder);
          futures.add(_gatherChildren(folder));
        }
      }
      return Future.wait(futures).then((_) => container);
    });
  }
}

abstract class Container extends Resource {
  List<Resource> _children = [];

  Container(Container parent, chrome_gen.Entry entry) : super(parent, entry);

  List<Resource> getChildren() => _children;
}

abstract class Resource {
  Container _parent;
  chrome_gen.Entry _entry;

  Resource(this._parent, this._entry);

  String get name => _entry.name;

  Container get parent => _parent;

  /**
   * Returns the containing [Project]. This can return null for loose files and
   * for the workspace.
   */
  Project get project => parent == null ? null : parent.project;
}

class Folder extends Container {
  Folder(Container parent, chrome_gen.Entry entry) : super(parent, entry);
}

class File extends Resource {
  File(Container parent, chrome_gen.Entry entry) : super(parent, entry);

  Future<String> getContents() => (_entry as chrome_gen.ChromeFileEntry).readText();

  Future setContents(String contents) => (_entry as chrome_gen.ChromeFileEntry).writeText(contents);
}

class Project extends Folder {
  Project(Container parent, chrome_gen.Entry entry) : super(parent, entry);

  Project get project => this;
}

class ResourceEventType {

  final String name;

  const ResourceEventType._(this.name);

  /**
   * Event type indicates resource has been added to workspace.
   */
  static const ResourceEventType ADD = const ResourceEventType._('ADD');

  /**
   * Event type indicates resource has been removed from workspace.
   */
  static const ResourceEventType DELETE = const ResourceEventType._('DELETE');

  /**
   * Event type indicates resource has changed.
   */
  static const ResourceEventType CHANGE = const ResourceEventType._('CHANGE');

  String toString() => name;

}

/**
 *  Used to indicate changes to the Workspace.
 */
class ResourceChangeEvent {

  final ResourceEventType type;
  final Resource resource;

  ResourceChangeEvent(this.resource, this.type);
}
