#  http://docs.cocoapods.org/specification.html

Pod::Spec.new do |s|

  s.name         = "SQLiteDataModel"
  s.version      = "0.2.0"
  s.summary      = "Taking advantage of Xcode's Core Data visual tools to manage pure SQLite schemas."

  s.description  = <<-DESC
SQLiteDataModel is able to create and migrate versions of SQLite databases using Data Model and Mapping Model documents, abandoning Core Data managed objects. Thus, you can visualy design a database model in Xcode and access it directly through the SQLite library or your favorite Swift wrapper.
                   DESC

  s.homepage     = "https://github.com/DnV1eX/SQLiteDataModel"
  # s.screenshots  = "www.example.com/screenshots_1.gif", "www.example.com/screenshots_2.gif"
  s.license      = "Apache License, Version 2.0"
  s.author       = { "Alexey Demin" => "dnv1ex@yahoo.com" }

  s.ios.deployment_target     = "10.0"
  s.osx.deployment_target     = "10.12"
  s.watchos.deployment_target = "3.0"
  s.tvos.deployment_target    = "10.0"

  s.source       = { :git => "https://github.com/DnV1eX/SQLiteDataModel.git", :tag => "#{s.version}" }
  s.source_files = "Sources/SQLiteDataModel/SQLiteDataModel.swift"
  s.framework    = "CoreData"
  s.library      = "sqlite3"

end
