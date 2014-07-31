// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.filesystem;

import 'dart:async';

import 'package:chrome/chrome_app.dart' as chrome;

import '../spark.dart';
import '../spark_flags.dart';
import '../test/files_mock.dart';
import 'workspace.dart' as ws;

FileSystemAccess _fileSystemAccess = null;
void setOverrideFilesystemAccess(FileSystemAccess fsa) {

}

FileSystemAccess get fileSystemAccess {
  if (_fileSystemAccess == null) {
    _fileSystemAccess = new FileSystemAccess._();
  }

  return _fileSystemAccess;
}

/**
 * Provides an abstracted access to the filesystem
 */
class FileSystemAccess {
  ws.WorkspaceRoot _root;
  ws.WorkspaceRoot get root {
    if (_root == null) {
      if (location.isSync) {
        _root = new ws.SyncFolderRoot(location.entry);
      } else {
        _root = new ws.FolderChildRoot(location.parent, location.entry);
      }
    }

    return _root;
  }

  void setOverrideRoot(ws.WorkspaceRoot root) {
    assert(_root == null);
    _root = root;
  }

  LocationResult location;

  FileSystemAccess._();

  Future<String> getDisplayPath(chrome.Entry entry) {
    return chrome.fileSystem.getDisplayPath(entry);
  }

  restoreManager(Spark spark) {
    return ProjectLocationManager.restoreManager(spark);
  }
}

class MockFileSystemAccess extends FileSystemAccess {
  MockFileSystemAccess() : super._();

  Future<String> getDisplayPath(chrome.Entry entry) {
    return new Future.value(entry.fullPath);
  }

  restoreManager(Spark spark) {
    return MockProjectLocationManager.restoreManager(spark);
  }
}

/**
 * Used to manage the default location to create new projects.
 *
 * This class also abstracts a bit other the differences between Chrome OS and
 * Windows/Mac/linux.
 */
class ProjectLocationManager {
  LocationResult _projectLocation;
  final Spark _spark;

  /**
   * Create a ProjectLocationManager asynchronously, restoring the default
   * project location from the given preferences.
   */
  static Future<ProjectLocationManager> restoreManager(Spark spark) {
    //localPrefs, workspace
    return spark.localPrefs.getValue('projectFolder').then((String folderToken) {
      if (folderToken == null) {
        return new ProjectLocationManager._(spark);
      }

      return chrome.fileSystem.restoreEntry(folderToken).then((chrome.Entry entry) {
        return _initFlagsFromProjectLocation(entry).then((_) {
          return new ProjectLocationManager._(spark,
              new LocationResult(entry, entry, false));
        });
      }).catchError((e) {
        return new ProjectLocationManager._(spark);
      });
    });
  }

  /**
   * Try to read and set the highest precedence developer flags from
   * "<project_location>/.spark.json".
   */
  static Future _initFlagsFromProjectLocation(chrome.DirectoryEntry projDir) {
    return projDir.getFile('.spark.json').then(
        (chrome.ChromeFileEntry flagsFile) {
      return SparkFlags.initFromFile(flagsFile.readText());
    }).catchError((_) {
      // Ignore missing file.
      return new Future.value();
    });
  }

  //this._prefs, this._workspace
  ProjectLocationManager._(this._spark, [this._projectLocation]);

  /**
   * Returns the default location to create new projects in. For Chrome OS, this
   * will be the sync filesystem. This method can return `null` if the user
   * cancels the folder selection dialog.
   */
  Future<LocationResult> getProjectLocation() {
    if (_projectLocation != null) {
      // Check if the saved location exists. If so, return it. Otherwise, get a
      // new location.
      return _projectLocation.exists().then((bool value) {
        if (value) {
          return _projectLocation;
        } else {
          _projectLocation = null;
          return getProjectLocation();
        }
      });
    }

    // On Chrome OS, use the sync filesystem.
    // TODO(grv): Enable syncfs once the api is more stable.
    /*if (PlatformInfo.isCros && _spark.workspace.syncFsIsAvailable) {
      return chrome.syncFileSystem.requestFileSystem().then((fs) {
        var entry = fs.root;
        return new LocationResult(entry, entry, true);
      });
    }*/

    // Show a dialog with explaination about what this folder is for.
    return chooseNewProjectLocation();
  }

  /**
   * Opens a pop up and asks the user to change the root directory. Internally,
   * the stored value is changed here.
   */
  Future<LocationResult> chooseNewProjectLocation() {
    // Show a dialog with explaination about what this folder is for.
    return _showRequestFileSystemDialog().then((bool accepted) {
      if (!accepted) {
        return null;
      }
      // Display a dialog asking the user to choose a default project folder.
      return selectFolder(suggestedName: 'projects').then((entry) {
        if (entry == null) return null;

        _projectLocation = new LocationResult(entry, entry, false);
        _spark.localPrefs.setValue('projectFolder',
            chrome.fileSystem.retainEntry(entry));
        return _projectLocation;
      });
    });
  }

  Future<bool> _showRequestFileSystemDialog() {
    return _spark.askUserOkCancel('Please choose a folder to store your Chrome Dev Editor projects.',
        okButtonLabel: 'Choose Folder', title: 'Choose top-level workspace folder');
  }

  /**
   * This will create a new folder in default project location. It will attempt
   * to use the given [defaultName], but will disambiguate it if necessary. For
   * example, if `defaultName` already exists, the created folder might be named
   * something like `defaultName-1` instead.
   */
  Future<LocationResult> createNewFolder(String defaultName) {
    return getProjectLocation().then((LocationResult root) {
      return root == null ? null : _create(root, defaultName, 1);
    });
  }

  Future<LocationResult> _create(
      LocationResult location, String baseName, int count) {
    String name = count == 1 ? baseName : '${baseName}-${count}';

    return location.parent.createDirectory(name, exclusive: true).then((dir) {
      return new LocationResult(location.parent, dir, location.isSync);
    }).catchError((_) {
      if (count > 50) {
        throw "Error creating project '${baseName}.'";
      } else {
        return _create(location, baseName, count + 1);
      }
    });
  }
}

class LocationResult {
  /**
   * The parent Entry. This can be useful for persistng the info across
   * sessions.
   */
  final chrome.DirectoryEntry parent;

  /**
   * The created location.
   */
  final chrome.DirectoryEntry entry;

  /**
   * Whether the entry was created in the sync filesystem.
   */
  final bool isSync;

  LocationResult(this.parent, this.entry, this.isSync);

  /**
   * The name of the created entry.
   */
  String get name => entry.name;

  Future<bool> exists() {
    if (isSync) return new Future.value(true);

    return entry.getMetadata().then((_) {
      return true;
    }).catchError((e) {
      return false;
    });
  }
}

class MockProjectLocationManager extends ProjectLocationManager {
  LocationResult _projectLocation;
  MockProjectLocationManager(Spark spark) : super._(spark);

  static Future<ProjectLocationManager> restoreManager(Spark spark) {
    return new Future.value(new MockProjectLocationManager(spark));
  }

  Future setupRoot() {
    if (_projectLocation != null) {
      return new Future.value(_projectLocation);
    }

    MockFileSystem fs = new MockFileSystem();
    DirectoryEntry rootParent = fs.createDirectory("rootParent");
    return rootParent.createDirectory("root").then((DirectoryEntry root) {
      _projectLocation = new LocationResult(rootParent, root, false);
    });
  }

  Future<LocationResult> getProjectLocation() {
    if (_projectLocation == null) {
      return super.getProjectLocation();
    } else {
      return new Future.value(_projectLocation);
    }
  }

  Future<LocationResult> createNewFolder(String name) {
//    setupRoot();
    return _projectLocation.entry.createDirectory(name, exclusive: true).then((dir) {
      return new LocationResult(_projectLocation.entry, dir, false);
    }).catchError((_) {
      throw "Error creating project '${name}.'";
    });
  }
}

/**
 * Allows a user to select a folder on disk. Returns the selected folder
 * entry. Returns `null` in case the user cancels the action.
 */
Future<chrome.DirectoryEntry> selectFolder({String suggestedName}) {
  Completer completer = new Completer();
  chrome.ChooseEntryOptions options = new chrome.ChooseEntryOptions(
      type: chrome.ChooseEntryType.OPEN_DIRECTORY);
  if (suggestedName != null) options.suggestedName = suggestedName;
  chrome.fileSystem.chooseEntry(options).then((chrome.ChooseEntryResult res) {
    completer.complete(res.entry);
  }).catchError((e) => completer.complete(null));
  return completer.future;
}

