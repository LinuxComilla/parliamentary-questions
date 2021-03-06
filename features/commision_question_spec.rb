require 'feature_helper'

feature 'Commissioning questions', js: true, suspend_cleaner: true do
  include Features::PqHelpers

  let(:ao)         { ActionOfficer.find_by(email: 'ao1@pq.com') }
  let(:ao2)        { ActionOfficer.find_by(email: 'ao2@pq.com') }
  let(:minister)   { Minister.first                             }

  before(:all) do
    clear_sent_mail
    DBHelpers.load_feature_fixtures
    @pq, _ =  PQA::QuestionLoader.new.load_and_import(2)
  end

  after(:all) do
    DatabaseCleaner.clean
  end

  scenario 'Parli-branch members tries to allocate a question without an answering minister' do
    create_pq_session
    visit dashboard_path
    within_pq(@pq.uin) do
      select_option('commission_form[policy_minister_id]', minister.name) if minister
      select ao.name, from: 'Action officer(s)'
      find("#internal-deadline input").set Date.tomorrow.strftime('%d/%m/%Y 12:00')
    end
    expect(page).not_to have_button("Commission")
  end

  scenario 'Parli-branch member allocates a question to selected AOs' do
    commission_question(@pq.uin, [ao, ao2], minister)
  end

  scenario 'AO should receive an email notification of assigned question' do
    ao_mail = sent_mail.first

    expect(ao_mail.to).to include ao.email
    expect(ao_mail.text_part.body).to include "your team is responsible for answering PQ #{@pq.uin}"

  end

  scenario 'Following the email link should let the AO accept the question' do
    visit_assignment_url(ao)
    choose 'Accept'
    click_on "Save"
    expect(page.title).to have_content("PQ assigned")
    expect(page).to have_content(/thank you for your response/i)
    expect(page).to have_content("PQ #{@pq.uin}")
  end

  scenario 'The PQ status should then change to draft pending' do
    create_pq_session
    expect_pq_in_progress_status(@pq.uin, 'Draft Pending')
  end

  scenario 'The AO should receive an email notification confirming the question acceptance' do
    ao_mail = sent_mail.last

    expect(ao_mail.to).to include ao.email
    expect(ao_mail.text_part.body).to include(
      "Thank you for agreeing to draft an answer to PQ #{@pq.uin}"
    )
  end

  scenario 'After an AO has accepted a question, another AO cannot accept the question' do
    ao2_mail = sent_mail_to(ao2.email).first
    ao2_link = extract_url_like('/assignment', ao2_mail)
    visit ao2_link

    expect(page.title).to have_content("PQ assignment")
    expect(page).to have_content(/this pq has already been accepted/i)
    expect(page).to have_content("#{ao.name} accepted PQ #{@pq.uin}")
  end

  scenario 'Following the link after 3 days have passed should show an error page' do
    form_params = {
      pq_id: Pq.last.id,
      minister_id: minister.id,
      action_officer_id: [ao.id],
      date_for_answer: Date.tomorrow,
      internal_deadline: Date.today
    }
    form = CommissionForm.new(form_params)
    CommissioningService.new(nil, Date.today - 4.days).commission(form)
    ao_mail, _ = sent_mail.last
    url = extract_url_like('/assignment', ao_mail)
    visit url
    expect(page.title).to have_content("Unauthorised (401)")
    expect(page).to have_content(/Link expired/i)
  end
end
