class Library < ActiveRecord::Base

  public_resource_for :read, :index

  has_many :tracks, :dependent => :destroy
  validates_presence_of :persistent_id, :name
  validates_uniqueness_of :name

  before_create :clean_strings
  def clean_strings
    name.strip! unless name.nil?
  end

  def display_name
    "'#{name}' (#{persistent_id})"
  end

  def self.create_for source
    find_or_create_with({
      :name => source.name
    }, {
      :persistent_id => source.persistent_id
    }, true)
  end

  def import
    if source.nil?
      puts "Source for #{display_name} not available, marking as offline."
      update_attribute :active, false
    else
      if new_or_deleted_before_save?
        puts "Importing new library #{display_name}."
      else
        puts "Re-importing library #{display_name}, currently #{tracks.count} tracks."
      end
      import_tracks
    end
  end

  def source
    detected_source = iTunes.sources.detect {|l| l.name == name }
    detected_source.library_playlists.first unless detected_source.nil?
  end

  def source_tracks
    if @source_tracks.nil?
      @source_tracks = {}
      source.tracks.each {|t|
        @source_tracks[t.persistent_id] = t if t.video_kind == OSA::ITunes::EVDK::NONE && !t.podcast?
      }
    end
    @source_tracks
  end

  private

  def import_tracks
    have = Track.persistent_ids_for self
    want = source_tracks.keys
    have_and_dont_want, want_and_dont_have = have - want, want - have

    if have_and_dont_want.empty? && want_and_dont_have.empty?
      puts "Nothing to update for #{display_name}."
    else
      original_track_count = tracks.count

      have_and_dont_want.each {|old_id| tracks.find_by_persistent_id(old_id).destroy }
      want_and_dont_have.each {|new_id| Track.import source_tracks[new_id], self }

      update_attribute :active, true
      touch :imported_at
      puts "Finished importing #{display_name} - library went from #{original_track_count} to #{tracks.count} tracks (#{want_and_dont_have.length} added, #{have_and_dont_want.length} removed).\n"
    end
  end

end
