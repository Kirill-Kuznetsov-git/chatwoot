json.meta do
  json.current_page @current_page
  # Для полного списка точное `count` не отдаём осознанно: подсчёт всех контактов
  # аккаунта стоил до 31 с и обрывался таймаутом роутера, навигация идёт по `has_more`
  # (см. комментарий у ContactsController#index). При фильтре по лейблам счётчик дешёвый,
  # поэтому там всё как раньше.
  if @total_count
    json.count @total_count
  else
    json.has_more @has_more
  end
end

json.payload do
  json.array! @contacts do |contact|
    json.partial! 'api/v1/models/contact', formats: [:json], resource: contact, with_contact_inboxes: @include_contact_inboxes
  end
end
