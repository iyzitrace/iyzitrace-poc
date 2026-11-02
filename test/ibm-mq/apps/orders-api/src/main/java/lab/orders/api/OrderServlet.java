package lab.orders.api;

import jakarta.jms.Connection;
import jakarta.jms.JMSException;
import jakarta.jms.MessageProducer;
import jakarta.jms.Session;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

/** POST or GET /orders-api/order: puts an order on ORDER.REQUEST of QM1. */
@WebServlet("/order")
public class OrderServlet extends HttpServlet {
  private Connection connection;

  private synchronized Connection connection() throws JMSException {
    if (connection == null) {
      connection = Mq.connect("QM1");
      connection.setExceptionListener(e -> reset());
    }
    return connection;
  }

  private synchronized void reset() {
    try {
      if (connection != null) connection.close();
    } catch (JMSException ignored) {
    }
    connection = null;
  }

  @Override
  protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
    String id = UUID.randomUUID().toString();
    int amount = ThreadLocalRandom.current().nextInt(10, 5000);
    try (Session session = connection().createSession(false, Session.AUTO_ACKNOWLEDGE)) {
      MessageProducer producer = session.createProducer(session.createQueue("ORDER.REQUEST"));
      producer.send(session.createTextMessage("{\"order\":\"" + id + "\",\"amount\":" + amount + "}"));
    } catch (JMSException e) {
      reset();
      throw new ServletException("order not sent", e);
    }
    resp.setStatus(HttpServletResponse.SC_ACCEPTED);
    resp.getWriter().println(id);
  }

  @Override
  protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
    doGet(req, resp);
  }

  @Override
  public void destroy() {
    reset();
  }
}
