package lab.orders.worker;

import com.ibm.mq.jakarta.jms.MQConnectionFactory;
import com.ibm.msg.client.jakarta.wmq.WMQConstants;
import jakarta.jms.Connection;
import jakarta.jms.JMSException;

/** A client connection to a queue manager, set up in code the way the customer's services do it. */
final class Mq {
  private Mq() {}

  /** MQ_QM1_CONNNAME=qm1(1414), MQ_APP_CHANNEL, MQ_APP_USER and MQ_APP_PASSWORD come from the server's environment. */
  static Connection connect(String queueManager) throws JMSException {
    MQConnectionFactory cf = new MQConnectionFactory();
    cf.setTransportType(WMQConstants.WMQ_CM_CLIENT);
    cf.setQueueManager(queueManager);
    cf.setConnectionNameList(System.getenv("MQ_" + queueManager + "_CONNNAME"));
    cf.setChannel(System.getenv("MQ_APP_CHANNEL"));
    cf.setBooleanProperty(WMQConstants.USER_AUTHENTICATION_MQCSP, true);
    return cf.createConnection(System.getenv("MQ_APP_USER"), System.getenv("MQ_APP_PASSWORD"));
  }
}
