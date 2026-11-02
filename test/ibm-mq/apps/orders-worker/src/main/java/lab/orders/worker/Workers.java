package lab.orders.worker;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import jakarta.ejb.Schedule;
import jakarta.ejb.Singleton;
import jakarta.ejb.Startup;
import jakarta.jms.Connection;
import jakarta.jms.JMSException;
import jakarta.jms.Message;
import jakarta.jms.MessageConsumer;
import jakarta.jms.MessageProducer;
import jakarta.jms.Session;
import jakarta.jms.TextMessage;
import java.util.concurrent.atomic.AtomicLong;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * The lab's message flow, with JMS message listeners:
 *
 * <pre>
 *   QM1 ORDER.REQUEST   -> every 25th order to QM1's dead-letter queue, the rest to QM1 PAYMENT.REMOTE,
 *                          which the channel QM1.TO.QM2 delivers to QM2 PAYMENT.REQUEST
 *   QM2 PAYMENT.REQUEST -> QM2 BILLING.REQUEST
 *   QM2 BILLING.REQUEST -> read only in even minutes, so its depth and oldest message rise and fall
 * </pre>
 */
@Singleton
@Startup
public class Workers {
  private static final Logger LOG = Logger.getLogger(Workers.class.getName());

  private final AtomicLong orders = new AtomicLong();
  private Connection qm1;
  private Connection qm2;
  private Connection billing;

  @PostConstruct
  void start() {
    ensureRunning();
  }

  /** Connects, or reconnects after a queue manager restart. */
  @Schedule(second = "*/30", minute = "*", hour = "*", persistent = false)
  synchronized void ensureRunning() {
    if (qm1 != null && qm2 != null && billing != null) return;
    stop();
    try {
      qm2 = Mq.connect("QM2");
      qm2.setExceptionListener(e -> restart());
      qm1 = Mq.connect("QM1");
      qm1.setExceptionListener(e -> restart());
      Session orderSession = qm1.createSession(false, Session.AUTO_ACKNOWLEDGE);
      MessageProducer deadLetters = orderSession.createProducer(orderSession.createQueue("SYSTEM.DEAD.LETTER.QUEUE"));
      MessageProducer payments = orderSession.createProducer(orderSession.createQueue("PAYMENT.REMOTE"));
      orderSession.createConsumer(orderSession.createQueue("ORDER.REQUEST")).setMessageListener(m -> {
        try {
          String body = ((TextMessage) m).getText();
          if (orders.incrementAndGet() % 25 == 0) {
            deadLetters.send(orderSession.createTextMessage(body));
          } else {
            payments.send(orderSession.createTextMessage(body));
          }
        } catch (JMSException e) {
          LOG.log(Level.WARNING, "order not forwarded", e);
        }
      });

      Session paymentSession = qm2.createSession(false, Session.AUTO_ACKNOWLEDGE);
      MessageProducer toBilling = paymentSession.createProducer(paymentSession.createQueue("BILLING.REQUEST"));
      paymentSession.createConsumer(paymentSession.createQueue("PAYMENT.REQUEST")).setMessageListener(m -> {
        try {
          toBilling.send(paymentSession.createTextMessage(((TextMessage) m).getText()));
        } catch (JMSException e) {
          LOG.log(Level.WARNING, "payment not forwarded", e);
        }
      });

      billing = Mq.connect("QM2");
      billing.setExceptionListener(e -> restart());
      Session billingSession = billing.createSession(false, Session.AUTO_ACKNOWLEDGE);
      MessageConsumer bills = billingSession.createConsumer(billingSession.createQueue("BILLING.REQUEST"));
      bills.setMessageListener(Workers::bill);

      qm2.start();
      qm1.start();
      toggleBilling();
      LOG.info("connected to QM1 and QM2");
    } catch (JMSException e) {
      LOG.log(Level.WARNING, "queue managers not reachable yet: " + e.getMessage());
      stop();
    }
  }

  /** Billing reads only in even minutes. */
  @Schedule(second = "0", minute = "*", hour = "*", persistent = false)
  synchronized void toggleBilling() {
    if (billing == null) return;
    try {
      if (java.time.LocalTime.now().getMinute() % 2 == 0) billing.start();
      else billing.stop();
    } catch (JMSException e) {
      LOG.log(Level.WARNING, "billing not toggled", e);
    }
  }

  private static void bill(Message m) {
    // the bill is "sent"; nothing else to do in the lab
  }

  private synchronized void restart() {
    stop();
  }

  @PreDestroy
  synchronized void stop() {
    for (Connection c : new Connection[] {qm1, qm2, billing}) {
      try {
        if (c != null) c.close();
      } catch (JMSException ignored) {
      }
    }
    qm1 = null;
    qm2 = null;
    billing = null;
  }
}
