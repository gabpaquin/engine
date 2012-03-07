require 'spec_helper'

describe Locomotive::ContentType do

  before(:each) do
    Locomotive::Site.any_instance.stubs(:create_default_pages!).returns(true)
  end

  context 'when validating' do

    it 'should have a valid factory' do
      content_type = FactoryGirl.build(:content_type)
      content_type.entries_custom_fields.build :label => 'anything', :type => 'string'
      content_type.should be_valid
    end

    # Validations ##

    %w{site name}.each do |field|
      it "requires the presence of #{field}" do
        content_type = FactoryGirl.build(:content_type, field.to_sym => nil)
        content_type.should_not be_valid
        content_type.errors[field.to_sym].should == ["can't be blank"]
      end
    end

    it 'requires the presence of slug' do
      content_type = FactoryGirl.build(:content_type, :name => nil, :slug => nil)
      content_type.should_not be_valid
      content_type.errors[:slug].should == ["can't be blank"]
    end

    it 'is not valid if slug is not unique' do
      content_type = FactoryGirl.build(:content_type)
      content_type.entries_custom_fields.build :label => 'anything', :type => 'string'
      content_type.save
      (content_type = FactoryGirl.build(:content_type, :site => content_type.site)).should_not be_valid
      content_type.errors[:slug].should == ["is already taken"]
    end

    it 'is not valid if there is not at least one field' do
      content_type = FactoryGirl.build(:content_type)
      content_type.should_not be_valid
      content_type.errors[:entries_custom_fields].should == { :base => ['At least, one custom field is required'] }
    end

    %w(created_at updated_at).each do |name|
      it "does not allow #{name} as name" do
        content_type = FactoryGirl.build(:content_type)
        field = content_type.entries_custom_fields.build :label => 'anything', :type => 'string', :name => name
        field.valid?.should be_false
        field.errors[:name].should == ['is reserved']
      end
    end

  end

  context '#ordered_entries' do

    before(:each) do
      (@content_type = build_content_type(:order_by => 'created_at')).save
      @content_2 = @content_type.entries.create :name => 'Sacha'
      @content_1 = @content_type.entries.create :name => 'Did'
    end

    it 'orders with the ASC direction by default' do
      @content_type.order_direction.should == 'asc'
    end

    it 'has a getter for manual order' do
      @content_type.order_manually?.should == false
      @content_type.order_by = '_position'
      @content_type.order_manually?.should == true
    end

    it 'returns a list of entries ordered manually' do
      @content_type.order_by = '_position'
      @content_type.ordered_entries.collect(&:name).should == %w(Sacha Did)
    end

    it 'returns a list of entries ordered by a column specified by order_by (ASC)' do
      @content_type.order_by = @content_type.entries_custom_fields.where(:name => 'name').first._id
      @content_type.ordered_entries.collect(&:name).should == %w(Did Sacha)
    end

    it 'returns a list of entries ordered by a column specified by order_by (DESC)' do
      @content_type.order_by = @content_type.entries_custom_fields.where(:name => 'name').first._id
      @content_type.order_direction = 'desc'
      @content_type.ordered_entries.collect(&:name).should == %w(Sacha Did)
    end

    it 'returns a list of entries ordered by a Date column when first instance is missing the value' do
      @content_type.order_by = @content_type.entries_custom_fields.where(:name => 'active_at').first._id
      @content_2.update_attribute :active_at, Date.parse('01/01/2001')
      content_3 = @content_type.entries.create :name => 'Mario', :active_at => Date.parse('02/02/2001')

      @content_type.ordered_entries.map(&:active_at).should == [nil, Date.parse('01/01/2001'), Date.parse('02/02/2001')]

      @content_type.order_direction = 'desc'
      @content_type.ordered_entries.map(&:active_at).should == [Date.parse('02/02/2001'), Date.parse('01/01/2001'), nil]
    end

  end

  context '#group_by belongs_to field' do

    before(:each) do
      (@category_content_type = build_content_type(:name => 'Categories')).save!
      @category_1 = @category_content_type.entries.create :name => 'A-developer'
      @category_2 = @category_content_type.entries.create :name => 'B-designer'

      @content_type = build_content_type.tap do |content_type|
        field = content_type.entries_custom_fields.build :label => 'Category', :type => 'belongs_to', :class_name => @category_1.class.to_s
        content_type.group_by_field_id = field._id
        content_type.save!
      end
      @content_1 = @content_type.entries.create :name => 'Sacha', :category => @category_2
      @content_2 = @content_type.entries.create :name => 'Did',   :category => @category_1
      @content_3 = @content_type.entries.create :name => 'Mario', :category => @category_1
    end

    it 'groups entries' do
      groups = @content_type.send(:group_by_belongs_to_field, @content_type.group_by_field)

      groups.map { |h| h[:name] }.should == %w(A-developer B-designer)

      groups.first[:entries].map(&:name).should == %w(Did Mario)
      groups.last[:entries].map(&:name).should == %w(Sacha)
    end

    it 'groups entries with a different columns order' do
      @category_content_type.update_attributes :order_by => @category_content_type.entries_custom_fields.first._id, :order_direction => 'desc'
      groups = @content_type.send(:group_by_belongs_to_field, @content_type.group_by_field)

      groups.map { |h| h[:name] }.should == %w(B-designer A-developer)
    end

    it 'deals with entries without a value for the group_by field (orphans)' do
      @content_type.entries.create :name => 'Paul'
      groups = @content_type.send(:group_by_belongs_to_field, @content_type.group_by_field)

      groups.map { |h| h[:name] }.should == ['A-developer', 'B-designer', nil]

      groups.last[:entries].map(&:name).should == %w(Paul)
    end

  end

  describe 'custom fields' do

    before(:each) do
      site = FactoryGirl.build(:site)
      Locomotive::Site.stubs(:find).returns(site)

      @content_type = build_content_type(:site => site)
      # Locomotive::ContentType.logger = Logger.new($stdout)
      # Locomotive::ContentType.db.connection.instance_variable_set(:@logger, Logger.new($stdout))
    end

    context 'validation' do

      %w{label type}.each do |key|
        it "should validate presence of #{key}" do
          field = @content_type.entries_custom_fields.build({ :label => 'Shortcut', :type => 'string' }.merge(key.to_sym => nil))
          field.should_not be_valid
          field.errors[key.to_sym].should == ["can't be blank"]
        end
      end

      it 'should not have unique label' do
        field = @content_type.entries_custom_fields.build :label => 'Active', :type => 'boolean'
        field.should_not be_valid
        field.errors[:label].should == ["is already taken"]
      end

      it 'should invalidate parent if custom field is not valid' do
        field = @content_type.entries_custom_fields.build
        @content_type.should_not be_valid
        @content_type.entries_custom_fields.last.errors[:label].should == ["can't be blank"]
      end

    end

    context 'define core attributes' do

      it 'should have an unique name' do
        @content_type.valid?
        @content_type.entries_custom_fields.first.name.should == 'name'
        @content_type.entries_custom_fields.last.name.should == 'active_at'
      end

    end

    context 'build and save' do

      before(:each) do
        @content_type.save
      end

      it 'should build asset' do
        asset = @content_type.entries.build
        lambda {
          asset.name
          asset.description
          asset.active
        }.should_not raise_error
      end

      it 'should assign values to newly built asset' do
        asset = build_content_entry(@content_type)
        asset.description.should == 'Lorem ipsum'
        asset.active.should == true
      end

      it 'should save asset' do
        asset = build_content_entry(@content_type)
        asset.save and @content_type.reload
        asset = @content_type.entries.first
        asset.description.should == 'Lorem ipsum'
        asset.active.should == true
      end

      it 'should not modify entries from another content type' do
        asset = build_content_entry(@content_type)
        asset.save and @content_type.reload
        another_content_type = Locomotive::ContentType.new
        lambda { another_content_type.entries.build.description }.should raise_error
      end

    end

    context 'modifying fields' do

      before(:each) do
        @content_type.save
        @asset = build_content_entry(@content_type).save
      end

      it 'adds new field' do
        @content_type.entries_custom_fields.build :label => 'Author', :name => 'author', :type => 'string'
        @content_type.save && @content_type.reload
        asset = @content_type.entries.first
        lambda { asset.author }.should_not raise_error
      end

      it 'removes a field' do
        @content_type.entries_custom_fields.destroy_all :conditions => { :name => 'active_at' }
        @content_type.save && @content_type.reload
        asset = @content_type.entries.first
        lambda { asset.active_at }.should raise_error
      end

      it 'renames field label' do
        @content_type.entries_custom_fields[1].label = 'Simple description'
        @content_type.entries_custom_fields[1].name = nil
        @content_type.save && @content_type.reload
        asset = @content_type.entries.first
        asset.simple_description.should == 'Lorem ipsum'
      end

    end

    context 'managing from hash' do

      it 'adds new field' do
        @content_type.entries_custom_fields.clear
        field = @content_type.entries_custom_fields.build :label => 'Title'
        @content_type.entries_custom_fields_attributes = { 0 => { :id => field.id.to_s, 'label' => 'A title', 'type' => 'string' }, 1 => { 'label' => 'Tagline', 'type' => 'sring' } }
        @content_type.entries_custom_fields.size.should == 2
        @content_type.entries_custom_fields.first.label.should == 'A title'
        @content_type.entries_custom_fields.last.label.should == 'Tagline'
      end

      it 'updates/removes fields' do
        @content_type.save

        field = @content_type.entries_custom_fields.build :label => 'Title', :type => 'string'
        @content_type.save

        @content_type.update_attributes(:entries_custom_fields_attributes => {
          '0' => { '_id' => lookup_field_id(1), 'label' => 'My Description', 'type' => 'text', '_destroy' => '1' },
          '1' => { '_id' => lookup_field_id(2), 'label' => 'Active', 'type' => 'boolean', '_destroy' => '1' },
          '2' => { '_id' => field._id, 'label' => 'My Title !' },
          '3' => { 'label' => 'Published at', 'type' => 'string' }
        })

        @content_type = Locomotive::ContentType.find(@content_type.id)

        @content_type.entries_custom_fields.size.should == 4
        @content_type.entries_custom_fields.map(&:name).should == %w(name active_at title published_at)
        @content_type.entries_custom_fields[2].label.should == 'My Title !'
      end

    end

  end

  def build_content_type(options = {})
    FactoryGirl.build(:content_type, options).tap do |content_type|
      content_type.entries_custom_fields.build :label => 'Name',        :type => 'string'
      content_type.entries_custom_fields.build :label => 'Description', :type => 'text'
      content_type.entries_custom_fields.build :label => 'Active',      :type => 'boolean'
      content_type.entries_custom_fields.build :label => 'Active at',   :type => 'date'
    end
  end

  def build_content_entry(content_type)
    content_type.entries.build(:name => 'Asset on steroids', :description => 'Lorem ipsum', :active => true)
  end

  def lookup_field_id(index)
    @content_type.entries_custom_fields.all[index].id.to_s
  end

end
