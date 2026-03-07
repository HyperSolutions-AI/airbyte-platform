import { FlexContainer } from "components/ui/Flex";

import { SimpleAuthLoginForm } from "area/auth/components/SimpleAuthLoginForm";

import styles from "./LoginPage.module.scss";

export const LoginPage = () => {
  return (
    <main className={styles.loginPage}>
      <div className={styles.loginPage__form}>
        <FlexContainer direction="column" gap="2xl">
          <FlexContainer justifyContent="center">
            <img src="/logo.png" width={601} height={400} alt="HyperFlow Logo" className="w-700" />
          </FlexContainer>
          <SimpleAuthLoginForm />
        </FlexContainer>
      </div>
    </main>
  );
};
