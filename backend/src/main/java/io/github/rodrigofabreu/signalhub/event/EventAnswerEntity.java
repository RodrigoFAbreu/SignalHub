package io.github.rodrigofabreu.signalhub.event;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.hibernate.annotations.Immutable;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * Persistence mapping of {@code event_answers}: how an event's question ended. Read through this
 * mapping; rows are only inserted by {@link EventAnswers}, with {@code ON CONFLICT DO NOTHING}, so
 * the primary key decides between two answers.
 */
@Entity
@Immutable
@Table(name = "event_answers")
class EventAnswerEntity {

  @Id
  @Column(name = "event_id")
  private UUID eventId;

  // ANSWER, or CLOSE when the producer closed the question.
  @Column(nullable = false)
  private String kind;

  @Column(name = "user_id")
  private UUID userId;

  @Column(name = "user_name")
  private String userName;

  private String via;

  @JdbcTypeCode(SqlTypes.ARRAY)
  @Column(name = "choice_ids")
  private String[] choiceIds;

  private String text;

  private String note;

  @Column(name = "answered_at", nullable = false)
  private Instant answeredAt;

  @Column(name = "client_id")
  private UUID clientId;

  protected EventAnswerEntity() {}

  UUID eventId() {
    return eventId;
  }

  boolean isClose() {
    return "CLOSE".equals(kind);
  }

  UUID userId() {
    return userId;
  }

  String userName() {
    return userName;
  }

  String via() {
    return via;
  }

  List<String> choiceIds() {
    return choiceIds == null ? List.of() : List.of(choiceIds);
  }

  String text() {
    return text;
  }

  String note() {
    return note;
  }

  Instant answeredAt() {
    return answeredAt;
  }

  UUID clientId() {
    return clientId;
  }
}
